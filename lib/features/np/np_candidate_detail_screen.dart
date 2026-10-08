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
import '../../core/pro_ui.dart';
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
  /// Whose pending CB attempt the recorded result is for (shown only with a spouse row).
  String _cbSubject = 'CANDIDATE';
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
      // With a spouse on record there are two attempts: decide the message on the
      // latest of each subject, the way the server does.
      final bySubject = <String, NpCbCheck>{};
      for (final cb in next.cbChecks) {
        bySubject[cb.subject] = cb;
      }
      final several = bySubject.length > 1;
      String label(NpCbCheck cb) => cb.subject == 'SPOUSE' ? 'spouse' : 'candidate';
      final rejected = bySubject.values.where((cb) => cb.status == 'REJECTED').toList();
      if (latest?.status == 'ERROR') {
        npToast(context, latest?.remarks ?? 'The credit bureau check could not be raised. Try again.', error: true);
      } else if (rejected.isNotEmpty) {
        final why = rejected.map((cb) => '${several ? '${label(cb)}: ' : ''}${cb.remarks ?? ''}').join('; ');
        npToast(context, 'Credit bureau rejected: $why', error: true);
      } else if (bySubject.isNotEmpty && bySubject.values.every((cb) => cb.status == 'APPROVED')) {
        final scores = bySubject.values
            .where((cb) => cb.score != null)
            .map((cb) => '${several ? '${label(cb)} score ' : 'score '}${cb.score}')
            .join(', ');
        npToast(context, 'Credit bureau approved${scores.isEmpty ? '' : ' ($scores)'}');
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
        message: approved
            ? 'Once every subject is approved the file moves to background verification.'
            : 'This ends the onboarding for this candidate.',
        confirmLabel: 'Record',
        danger: !approved)) {
      return;
    }
    await _run(
      'CB result',
      () => ref.read(npRepositoryProvider).recordCbResult(
            _id,
            status: _cbResult,
            subject: _cbSubject,
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

  /// NP_CB_OVERRIDE holders only (the server decides): waves a CB rejection through to BGV.
  Future<void> _overrideCb() async {
    if (!await npConfirm(context,
        title: 'Override credit bureau rejection?',
        message: "The bureau's verdict stays on record. The candidate continues to background verification as if approved, "
            'and your reason is written to the audit trail.',
        confirmLabel: 'Continue',
        danger: true)) {
      return;
    }
    final remarks = await npPrompt(context,
        title: 'Justification for overriding', label: 'Reason (required, audited)', confirmLabel: 'Override & continue', danger: true);
    if (remarks == null) return;
    await _run('CB override', () => ref.read(npRepositoryProvider).overrideCbRejection(_id, remarks));
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
    final done = d == null ? 0 : d.steps.where((s) => s.state == 'DONE').length;
    return Scaffold(
      appBar: AppBar(
        title: Text(d?.candidateCode ?? 'NP candidate'),
        actions: [
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
              : ProPage(
                  onRefresh: _load,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  hero: _hero(d, done),
                  children: [
                    if (_error != null) AppErrorPanel(message: _error!, onRetry: _load),
                    if (d.status == 'SENT_BACK_FOR_CORRECTION') _correctionBanner(d),
                    if (d.rejected) _rejectionBanner(d),
                    if (d.cbOverrideAt != null) _cbOverrideBanner(d),
                    GlassCard(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        const ProSectionHeader(
                          title: 'Onboarding progress',
                          trailing: Text('Tap a step to open it', style: AppText.caption),
                        ),
                        const SizedBox(height: 10),
                        NpStepper(steps: d.steps, selected: d.step, onSelect: (s) => setState(() => _open.add(s))),
                      ]),
                    ),
                    ProSectionHeader(
                      title: 'Onboarding checklist',
                      small: true,
                      trailing: Text('$done of ${kNpSteps.length} done',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted,
                            fontFeatures: [FontFeature.tabularFigures()],
                          )),
                    ),
                    ProListGroup(
                      dividerIndent: 0,
                      children: [
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
                      ],
                    ),
                    if (d.supersededDocuments.isNotEmpty)
                      GlassCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          const ProSectionHeader(title: 'Replaced documents'),
                          const SizedBox(height: 12),
                          NpDocumentList(documents: d.supersededDocuments),
                        ]),
                      ),
                    if (d.can('VIEW_AUDIT')) _auditCard(),
                  ],
                ),
    );
  }

  Widget _panel(int index, String step, NpCandidateDetail d, List<Widget> children) {
    final info = kNpSteps[index - 1];
    return NpStepPanel(
      index: index,
      title: info.label,
      view: d.stepView(step),
      open: _open.contains(step),
      onToggle: () => _toggle(step),
      children: children,
    );
  }

  /// Deep hero: identity + tags, where the file stands, quick actions and the
  /// at-a-glance KPI strip.
  Widget _hero(NpCandidateDetail d, int done) {
    final photo = Env.fileUrl(d.photo?.url);
    var stepNo = kNpSteps.indexWhere((s) => s.step == d.step);
    final stepLabel = stepNo < 0 ? npTitle(d.step) : kNpSteps[stepNo].label;
    stepNo = stepNo < 0 ? 0 : stepNo + 1;

    final String live;
    final Color liveColor;
    if (d.finalActivatedAt != null) {
      live = 'Active NP since ${npFmtDateTime(d.finalActivatedAt)}';
      liveColor = AppColors.live;
    } else if (d.rejected) {
      live = '${npStatusLabel(d.status)} · ${npFmtDateTime(d.rejectedAt)}';
      liveColor = const Color(0xFFE5484D);
    } else {
      live = '${stepNo > 0 ? 'Step $stepNo of ${kNpSteps.length} · ' : ''}$stepLabel'
          '${d.updatedAt != null ? ' · updated ${npFmtDate(d.updatedAt)}' : ''}';
      liveColor = d.status == 'SENT_BACK_FOR_CORRECTION' || d.status.endsWith('_PENDING')
          ? const Color(0xFFF2B347)
          : AppColors.live;
    }

    String? lastScore(bool spouse) {
      for (final cb in d.cbChecks.reversed) {
        if ((cb.subject == 'SPOUSE') == spouse && cb.score != null && cb.score!.isNotEmpty) return cb.score;
      }
      return null;
    }

    final cbScore = lastScore(false);
    final spouseScore = lastScore(true);

    final actions = <ProAction>[
      if (d.can('RESUBMIT')) ProAction(icon: Icons.replay_rounded, label: 'Resubmit', onTap: _busy ? null : _resubmit),
      if (d.can('BGV_DRAFT') || d.can('BGV_SUBMIT'))
        ProAction(icon: Icons.home_work_outlined, label: 'BGV visit', onTap: _busy ? null : _openBgv),
      if (d.can('SUBMIT_AGREEMENT'))
        ProAction(icon: Icons.description_outlined, label: 'Agreement', onTap: _busy ? null : _openAgreement),
      if (d.can('EDIT'))
        ProAction(
          icon: Icons.edit_outlined,
          label: 'Edit',
          onTap: _busy
              ? null
              : () async {
                  final changed = await context.push<bool>('/np/candidates/$_id/edit');
                  if (changed == true) _load();
                },
        ),
      if (d.can('DELETE')) ProAction(icon: Icons.delete_outline_rounded, label: 'Delete', onTap: _busy ? null : _delete),
    ];

    return ProHero(
      overlap: ProKpiStrip(cells: [
        ProKpi(value: '$done / ${kNpSteps.length}', label: 'Steps done', progress: done / kNpSteps.length),
        ProKpi(value: '${d.documents.length}', label: 'Documents'),
        ProKpi(value: cbScore ?? '—', label: 'CB score'),
        if (spouseScore != null) ProKpi(value: spouseScore, label: 'Spouse CB score'),
      ]),
      children: [
        _CandidateIdentity(
          name: d.fullName,
          photoUrl: photo,
          lines: [
            '${d.candidateCode} · ${d.mobileNumber}',
            if (d.orgLine.isNotEmpty) d.orgLine,
          ],
          tags: [
            ProHeroTag(d.statusLabel, tone: npStatusTagTone(d.status)),
            if (d.npId != null) ProHeroTag('NP ID ${d.npId}', icon: Icons.badge_outlined),
            if (d.esafId != null) ProHeroTag('ESAF ${d.esafId}'),
            if (d.activationException) const ProHeroTag('Activation exception', tone: ProTagTone.warn),
          ],
        ),
        ProLiveLine(text: live, color: liveColor),
        if (actions.isNotEmpty) ProHeroActions(actions: [for (var i = 0; i < actions.length; i++) _primaryIf(actions[i], i == 0)]),
      ],
    );
  }

  static ProAction _primaryIf(ProAction a, bool primary) =>
      ProAction(icon: a.icon, label: a.label, onTap: a.onTap, primary: primary);

  /// Key / value block; empty values read "—".
  Widget _kv(List<(String, String?)> rows) => ProKeyValue(rows: [
        for (final r in rows) MapEntry(r.$1, (r.$2 == null || r.$2!.trim().isEmpty) ? '—' : r.$2!),
      ]);

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
        body: [
          if (d.rejectionReason != null) d.rejectionReason!,
          'Rejected on ${npFmtDateTime(d.rejectedAt)}',
          if (d.can('CB_OVERRIDE')) 'You hold the override permission. A justification is required and is audited.',
        ].join('\n'),
        action: d.can('CB_OVERRIDE')
            ? FilledButton.icon(
                style: npDangerButtonStyle(),
                onPressed: _busy ? null : _overrideCb,
                icon: const Icon(Icons.gavel_rounded, size: 18),
                label: const Text('Override CB rejection & continue to BGV'),
              )
            : null,
      );

  /// The bureau said no, an authorised person waved the candidate through.
  Widget _cbOverrideBanner(NpCandidateDetail d) => NpBanner(
        icon: Icons.gavel_rounded,
        color: const Color(0xFFD97706),
        title: 'Credit bureau rejection overridden',
        body: [
          if (d.cbOverrideRemarks != null) d.cbOverrideRemarks!,
          'By ${d.cbOverrideBy?.name ?? 'an authorised user'} on ${npFmtDateTime(d.cbOverrideAt)}',
        ].join('\n'),
      );

  // ── 1. Candidate ──
  List<Widget> _candidatePanel(NpCandidateDetail d) {
    final branch = Branding.current.term('branch');
    return [
      _kv([
        ('Gender', npTitle(d.gender)),
        ('Date of birth', npFmtDate(d.dateOfBirth)),
        ("Father's name", d.fatherOrSpouseName),
        ('Marital status', npTitle(d.maritalStatus)),
        if (d.spouseName != null) ('Spouse', d.spouseName),
        if (d.spouseDateOfBirth != null) ('Spouse DOB', npFmtDate(d.spouseDateOfBirth)),
        if (d.spouseMobile != null) ('Spouse mobile', d.spouseMobile),
        if (d.spouseOccupation != null) ('Spouse occupation', d.spouseOccupation),
        if (d.spouseFatherName != null) ("Spouse's father", d.spouseFatherName),
        if (d.spouseAadhaarLast4 != null) ('Spouse Aadhaar', '•••• ${d.spouseAadhaarLast4}'),
        if (d.spousePanNumber != null) ('Spouse PAN', d.spousePanNumber),
        if (d.spouseDrivingLicenceNumber != null) ('Spouse driving licence', d.spouseDrivingLicenceNumber),
        ('Alternate mobile', d.alternateMobile),
        ('Email', d.email),
        ('Education', d.education),
        ('Occupation', d.occupation),
        ('Experience', d.experienceYears == null ? null : '${d.experienceYears} yr'),
        ('Two-wheeler', d.hasTwoWheeler == true ? 'Yes' : 'No'),
        ('Smartphone', d.hasSmartphone == true ? 'Yes' : 'No'),
        ('Aadhaar', d.aadhaarLast4 == null ? null : '•••• ${d.aadhaarLast4}'),
        ('PAN', d.panNumber),
        ('Driving licence', d.drivingLicenceNumber),
        ('Bank', d.bankName),
        ('Account', d.bankAccountNumber),
        ('IFSC', d.bankIfsc),
        ('Name as per bank', d.bankAccountHolderName),
        ('Permanent address', d.permanentAddress),
        ('Comm. address', d.communicationAddress),
        (branch, d.branchName),
      ]),
      if (d.eligibility.isNotEmpty)
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const NpFieldLabel('Eligibility'),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final e in d.eligibility.entries) NpChip(e.key, on: e.value)]),
          if (d.eligibilityNotes != null) ...[
            const SizedBox(height: 8),
            Text(d.eligibilityNotes!, style: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.inkSoft)),
          ],
        ]),
      if (d.remarks != null && d.remarks!.isNotEmpty)
        Text(d.remarks!, style: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.inkSoft)),
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
          const ProIconWell(icon: Icons.check_rounded, color: AppColors.success),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Completed on ${npFmtDate(d.orientationDate)}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
              NpPersonStamp(person: d.orientationBy, at: d.orientationAt),
            ]),
          ),
        ]),
      if (d.can('ORIENTATION'))
        NpActionBox(
          title: 'Cover each orientation item',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (items.isEmpty)
              const Text('No orientation items configured.', style: _muted),
            for (final item in items)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(item, style: const TextStyle(fontSize: 14)),
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
          const Text('No interview recorded yet.', style: _muted),
        for (final iv in d.interviews)
          _historyCard(
            leading: iv.result == 'PASS' ? ProPill.ok('Pass') : ProPill.bad('Fail'),
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
                style: _ivResult == 'REJECT' ? npDangerButtonStyle() : null,
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
          const Text('Missing mandatory:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF9A5B00))),
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
                  textAlign: TextAlign.center, style: AppText.caption),
            ),
        ]),
    ];
  }

  // ── 5. CB check ──
  List<Widget> _cbPanel(NpCandidateDetail d) => [
        if (d.cbChecks.isEmpty)
          const Text('No CB check has been raised yet.', style: _muted),
        for (final cb in d.cbChecks)
          _historyCard(
            leading: npTonePill(
              npTitle(cb.status),
              cb.status == 'APPROVED'
                  ? AppColors.success
                  : (cb.status == 'REJECTED' || cb.status == 'ERROR')
                      ? AppColors.danger
                      : AppColors.warning,
            ),
            title: '${cb.subject == 'SPOUSE' ? 'Spouse' : 'Candidate'} · Attempt ${cb.attemptNo}${cb.referenceNo != null ? ' · Ref ${cb.referenceNo}' : ''}',
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
                    style: TextButton.styleFrom(minimumSize: const Size(0, 32), visualDensity: VisualDensity.compact),
                    onPressed: () => npOpenFile(context, cb.report),
                    icon: const Icon(Icons.description_outlined, size: 16),
                    label: const Text('Report'),
                  ),
          ),
        if (d.can('SUBMIT_CB'))
          FilledButton.icon(
            onPressed: _busy ? null : _submitCb,
            icon: const Icon(Icons.credit_score_rounded, size: 18),
            label: const Text('Submit for CB check'),
          ),
        if (d.can('CB_OVERRIDE'))
          FilledButton.icon(
            style: npDangerButtonStyle(),
            onPressed: _busy ? null : _overrideCb,
            icon: const Icon(Icons.gavel_rounded, size: 18),
            label: const Text('Override CB rejection & continue to BGV'),
          ),
        if (d.can('RECORD_CB_RESULT'))
          NpActionBox(
            title: 'Record the bureau result',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (d.cbChecks.any((cb) => cb.subject == 'SPOUSE')) ...[
                const NpFieldLabel('Whose result'),
                DropdownButtonFormField<String>(
                  value: _cbSubject,
                  items: const [
                    DropdownMenuItem(value: 'CANDIDATE', child: Text('Candidate')),
                    DropdownMenuItem(value: 'SPOUSE', child: Text('Spouse')),
                  ],
                  onChanged: (v) => setState(() => _cbSubject = v ?? 'CANDIDATE'),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 5, bottom: 2),
                  child: Text('The file moves on only once both the candidate and the spouse are approved.', style: AppText.caption),
                ),
              ],
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
                style: _cbResult == 'REJECTED' ? npDangerButtonStyle() : null,
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
        const Text('No BGV report submitted yet.', style: _muted),
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
        FilledButton.icon(
          style: npDangerButtonStyle(),
          onPressed: _busy ? null : _rejectBgv,
          icon: const Icon(Icons.block_rounded, size: 18),
          label: const Text('Reject at BGV'),
        ),
    ];
  }

  Widget _bgvReportCard(NpBgvReport r) => Container(
        padding: const EdgeInsets.all(14),
        decoration: _boxDecoration,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('Visit #${r.attemptNo} · ${npFmtDateTime(r.visitAt)}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink, fontFeatures: [FontFeature.tabularFigures()])),
            ),
            if (r.recommendation != null)
              r.recommendation == 'RECOMMENDED' ? ProPill.ok('Recommended') : ProPill.bad('Not recommended'),
          ]),
          const SizedBox(height: 6),
          _kv([
            ('Address verified', r.addressVerified == true ? 'Yes' : 'No'),
            ('Address as found', r.addressAsFound),
            ('Residence type', npTitle(r.residenceType)),
            ('Years at address', r.yearsAtAddress?.toString()),
          ]),
          if (r.latitude != null && r.longitude != null)
            TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 34), visualDensity: VisualDensity.compact),
              onPressed: () => npOpenMaps(r.latitude!, r.longitude!),
              icon: const Icon(Icons.place_outlined, size: 16),
              label: Text('${r.latitude!.toStringAsFixed(5)}, ${r.longitude!.toStringAsFixed(5)}'
                  '${r.locationAccuracyM != null ? ' (±${r.locationAccuracyM!.round()} m)' : ''}'),
            ),
          if (r.familyMembers.isNotEmpty) ...[
            const NpFieldLabel('Family members'),
            for (final m in r.familyMembers)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                    '• ${m.name} — ${m.relation}${m.age != null ? ', ${m.age} yrs' : ''}${m.occupation != null && m.occupation!.isNotEmpty ? ', ${m.occupation}' : ''}',
                    style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.inkSoft)),
              ),
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
            const SizedBox(height: 8),
            Text(r.amRemarks!, style: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.inkSoft)),
          ],
          const SizedBox(height: 10),
          NpDocumentList(documents: r.photos, emptyText: 'No visit photos.'),
          const SizedBox(height: 6),
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
              const SizedBox(height: 6),
              FilledButton.icon(
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
              FilledButton.icon(
                style: npDangerButtonStyle(),
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
          const Text('No agreement submitted yet.', style: _muted),
        for (final ag in d.agreements)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
            decoration: _boxDecoration,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text('Agreement #${ag.attemptNo} · ${npFmtDate(ag.agreementDate)}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink, fontFeatures: [FontFeature.tabularFigures()])),
                ),
                if (ag.file != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(minimumSize: const Size(0, 32), visualDensity: VisualDensity.compact),
                    onPressed: () => npOpenFile(context, ag.file),
                    icon: const Icon(Icons.open_in_new_rounded, size: 15),
                    label: const Text('Open'),
                  ),
              ]),
              for (final p in ag.pdcs)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    const ProIconWell(icon: Icons.payments_outlined, size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('PDC ${p.seqNo} · Cheque ${p.chequeNumber}',
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.ink, fontFeatures: [FontFeature.tabularFigures()])),
                        Text([p.bankName, p.ifsc, p.accountNumber].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                            style: const TextStyle(fontSize: 12, color: AppColors.muted, fontFeatures: [FontFeature.tabularFigures()])),
                      ]),
                    ),
                    if (p.file != null)
                      IconButton(
                        tooltip: 'Open cheque scan',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => npOpenFile(context, p.file),
                        icon: Icon(Icons.image_outlined, size: 19, color: AppColors.primary),
                      ),
                  ]),
                ),
              if (ag.verificationVideo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    const ProIconWell(icon: Icons.videocam_outlined, size: 30),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Customer verification video',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.ink)),
                    ),
                    IconButton(
                      tooltip: 'Play video',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => npOpenFile(context, ag.verificationVideo),
                      icon: Icon(Icons.play_circle_outline_rounded, size: 21, color: AppColors.primary),
                    ),
                  ]),
                ),
              if (ag.remarks != null && ag.remarks!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(ag.remarks!, style: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.inkSoft)),
              ],
              const SizedBox(height: 6),
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
              FilledButton.icon(
                style: npDangerButtonStyle(),
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
          const Text('Generated automatically on OPS approval.', style: _muted)
        else
          _kv([
            ('NP ID', d.npId),
            ('Generated at', npFmtDateTime(d.npIdGeneratedAt)),
          ]),
      ];

  // ── 11. App activation ──
  List<Widget> _activationPanel(NpCandidateDetail d) {
    final pending = d.activations.where((a) => a.verifiedAt == null).isNotEmpty;
    return [
      if (d.activations.isEmpty)
        const Text('The app has not been activated yet.', style: _muted),
      for (final a in d.activations)
        _historyCard(
          leading: npTonePill(
            a.verifiedAt != null ? 'Verified' : (a.exceptionReason != null ? 'Exception' : 'OTP sent'),
            a.verifiedAt != null ? AppColors.success : (a.exceptionReason != null ? AppColors.warning : AppColors.info),
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
              style: const TextStyle(fontSize: 18, letterSpacing: 6, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
              decoration: const InputDecoration(hintText: '6 digits'),
            ),
            const SizedBox(height: 6),
            Text('Device: ${[_deviceModel, _deviceOs, _appVersion].whereType<String>().join(' · ')}', style: AppText.caption),
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
        _kv([
          ('ESAF ID', d.esafId),
          ('Created at', npFmtDateTime(d.esafIdCreatedAt)),
          if (d.esafIdBy != null) ('Created by', d.esafIdBy!.name),
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
          ProNote(
            'Active NP since ${npFmtDateTime(d.finalActivatedAt)}${d.finalActivatedBy != null ? ' · by ${d.finalActivatedBy!.name}' : ''}',
            tone: ProNoteTone.ok,
            icon: Icons.verified_rounded,
          ),
        if (d.can('FINAL_ACTIVATE'))
          FilledButton.icon(
            onPressed: _busy ? null : _finalActivate,
            icon: const Icon(Icons.rocket_launch_rounded, size: 18),
            label: const Text('Mark as Active NP'),
          ),
      ];

  /// Audit trail as a vertical timeline.
  Widget _auditCard() => GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const ProSectionHeader(title: 'Audit trail'),
          const SizedBox(height: 12),
          if (_audit.isEmpty) const Text('No audit entries.', style: _muted),
          for (var i = 0; i < _audit.length; i++)
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(
                  width: 18,
                  child: Column(children: [
                    const SizedBox(height: 4),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: i == 0 ? AppColors.primary : AppColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: i == 0 ? AppColors.primary : const Color(0xFFC6D3D6), width: 2),
                      ),
                    ),
                    if (i < _audit.length - 1)
                      Expanded(child: Container(width: 2, margin: const EdgeInsets.only(top: 3), color: AppColors.hairlineSoft)),
                  ]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: i < _audit.length - 1 ? 14 : 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Text(npTitle(_audit[i].action),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
                        ),
                        const SizedBox(width: 8),
                        Text(npFmtDateTime(_audit[i].createdAt),
                            style: const TextStyle(fontSize: 12, color: AppColors.muted, fontFeatures: [FontFeature.tabularFigures()])),
                      ]),
                      const SizedBox(height: 1),
                      Text('${npStatusLabel(_audit[i].previousStatus)} → ${npStatusLabel(_audit[i].newStatus)}',
                          style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.inkSoft)),
                      Text(
                          [_audit[i].performedBy ?? '—', if (_audit[i].roles != null && _audit[i].roles!.isNotEmpty) _audit[i].roles!]
                              .join(' · '),
                          style: AppText.caption),
                      if ((_audit[i].remarks ?? _audit[i].detail) != null)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(10)),
                          child: Text((_audit[i].remarks ?? _audit[i].detail)!,
                              style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.inkSoft)),
                        ),
                    ]),
                  ),
                ),
              ]),
            ),
        ]),
      );

  // ── helpers ──

  static const _muted = TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted);

  static final _boxDecoration = BoxDecoration(
    color: AppColors.surfaceAlt,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: AppColors.hairlineSoft),
  );

  Widget _approvalHistory(List<NpApproval> approvals, String emptyText) {
    if (approvals.isEmpty) return Text(emptyText, style: _muted);
    return Column(children: [
      for (final a in approvals)
        _historyCard(
          leading: npTonePill(
            npTitle(a.action),
            a.action == 'APPROVE' ? AppColors.success : (a.action == 'REJECT' ? AppColors.danger : AppColors.warning),
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
        padding: EdgeInsets.fromLTRB(12, trailing == null ? 11 : 6, trailing == null ? 12 : 4, 11),
        decoration: _boxDecoration,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            leading,
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink, fontFeatures: [FontFeature.tabularFigures()])),
            ),
            if (trailing != null) trailing,
          ]),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l, style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.inkSoft)),
            ),
          if (stamp != null) Padding(padding: const EdgeInsets.only(top: 4), child: stamp),
        ]),
      );

  Widget _dateField(DateTime value, ValueChanged<DateTime> onPicked) => InkWell(
        onTap: () async {
          final d = await showDatePicker(context: context, initialDate: value, firstDate: DateTime(2020), lastDate: DateTime(2035));
          if (d != null) onPicked(d);
        },
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: InputDecorator(
          decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today_outlined, size: 18)),
          child: Text(npFmtDate(value), style: const TextStyle(fontSize: 15, color: AppColors.ink)),
        ),
      );
}

/// Identity block for the candidate hero: photo (or initials) in a white
/// squircle with a lime ring, name, code / org lines and status tags.
class _CandidateIdentity extends StatelessWidget {
  const _CandidateIdentity({required this.name, required this.photoUrl, required this.lines, required this.tags});
  final String name;
  final String? photoUrl;
  final List<String> lines;
  final List<ProHeroTag> tags;

  @override
  Widget build(BuildContext context) {
    final initials = Text(
      ProAvatar.initialsOf(name),
      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600, letterSpacing: -0.4, color: AppColors.deep),
    );
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 64,
        height: 64,
        margin: const EdgeInsets.only(top: 4, left: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: AppColors.deep, spreadRadius: 3),
            const BoxShadow(color: AppColors.live, spreadRadius: 5),
          ],
        ),
        alignment: Alignment.center,
        child: photoUrl == null
            ? initials
            : ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.network(photoUrl!, width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, __, ___) => initials),
              ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 22, height: 1.22, fontWeight: FontWeight.w600, letterSpacing: -0.55, color: Colors.white),
          ),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(l,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 1.35, color: Colors.white70, fontFeatures: [FontFeature.tabularFigures()])),
            ),
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Wrap(spacing: 6, runSpacing: 6, children: tags),
            ),
        ]),
      ),
    ]);
  }
}

// Employee autocomplete backed by `/api/employees/lookup` (interviewer picker).
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
