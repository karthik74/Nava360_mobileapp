// ─────────────────────────────────────────────────────────────────────────────
//  NP Onboarding — Agreement & PDC submission (BM after DM approval).
//  Route: /np/candidates/:id/agreement
//
//  Rules (server-enforced, mirrored here): signed agreement scan + date, two
//  post-dated cheques each with a 6-digit cheque number and a scan, account +
//  IFSC required and identical on both cheques (PDC 2 mirrors PDC 1), cheque
//  numbers distinct. Amount and cheque date are not captured (cheques are
//  collected blank).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'np_models.dart';
import 'np_repository.dart';
import 'np_widgets.dart';

final _ifscRe = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');

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
    try {
      await ref.read(npRepositoryProvider).submitAgreement(
            _id,
            agreementPath: _agreementFile!.path,
            pdc1Path: _pdc1File!.path,
            pdc2Path: _pdc2File!.path,
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(void Function(NpPickedFile f) set) async {
    final f = await npPickAnyFile(context);
    if (f != null) setState(() => set(f));
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final allowed = d?.can('SUBMIT_AGREEMENT') ?? false;
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Agreement & PDCs'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : d == null
                ? Padding(padding: const EdgeInsets.all(16), child: AppErrorPanel(message: _error ?? 'Not found', onRetry: _load))
                : !allowed
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: AppEmptyState(icon: Icons.lock_outline_rounded, message: 'The agreement cannot be submitted at this stage (${d.statusLabel}).'),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        children: [
                          GlassCard(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(d.fullName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
                              Text('${d.candidateCode} · ${d.mobileNumber}', style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                            ]),
                          ),
                          const SizedBox(height: 10),
                          if (d.status == 'SENT_BACK_FOR_CORRECTION' && d.correctionRemarks != null) ...[
                            NpBanner(icon: Icons.undo_rounded, color: const Color(0xFFEA580C), title: 'Sent back — resubmit the agreement', body: d.correctionRemarks),
                            const SizedBox(height: 10),
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
                                decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today_rounded, size: 18)),
                                child: Text(npFmtDate(_agreementDate), style: const TextStyle(fontSize: 14, color: AppColors.ink)),
                              ),
                            ),
                            NpFilePickField(
                              label: 'Signed agreement scan',
                              fileName: _agreementFile?.name,
                              onPick: () => _pick((f) => _agreementFile = f),
                            ),
                          ]),
                          _card('Cheque account', [
                            const Text('Both post-dated cheques are drawn on this account.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
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
                          _card('Remarks', [
                            TextField(controller: _remarks, minLines: 2, maxLines: 4, textCapitalization: TextCapitalization.sentences),
                          ]),
                          SizedBox(
                            height: 50,
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _submit,
                              icon: _busy
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.send_rounded, size: 18),
                              label: Text(_busy ? 'Uploading…' : 'Submit agreement & PDCs'),
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }

  Widget _pdcCard(int seq, TextEditingController no, NpPickedFile? file, void Function(NpPickedFile f) setFile) => _card('PDC $seq', [
        const NpFieldLabel('Cheque number', required: true),
        TextField(
          controller: no,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          decoration: const InputDecoration(hintText: '6 digits'),
        ),
        NpFilePickField(label: 'Cheque scan', fileName: file?.name, onPick: () => _pick(setFile)),
      ]);

  Widget _card(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 4),
            ...children,
          ]),
        ),
      );
}
