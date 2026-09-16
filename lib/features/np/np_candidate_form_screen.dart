// ─────────────────────────────────────────────────────────────────────────────
//  NP Onboarding — create / edit a candidate (the DRAFT that starts the file).
//  Routes: /np/candidates/new  ·  /np/candidates/:id/edit
//  Mirrors the web NpCandidateFormPage: 9 sections, Aadhaar quick-fill via
//  DigiLocker (when the server has the vendor configured), penny-less bank
//  verification, photo upload through /api/files.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/branding.dart';
import '../../core/env.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../files/file_repository.dart';
import '../requisitions/requisition_models.dart';
import '../requisitions/requisition_repository.dart';
import 'np_models.dart';
import 'np_repository.dart';
import 'np_widgets.dart';

/// Branches the caller may post a candidate to: their own scope when the
/// login carries branch ids, otherwise every active branch (HR / admin).
final _npBranchesProvider = FutureProvider.autoDispose<List<BranchOption>>((ref) async {
  final all = await ref.watch(requisitionRepositoryProvider).listBranches();
  final scope = ref.watch(authUserProvider)?.branchIds ?? const <int>{};
  final list = all.where((b) => b.active && (scope.isEmpty || scope.contains(b.id))).toList()
    ..sort((a, b) => a.label.compareTo(b.label));
  return list.isEmpty ? (all.where((b) => b.active).toList()..sort((a, b) => a.label.compareTo(b.label))) : list;
});

final _panRe = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
final _ifscRe = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');

class NpCandidateFormScreen extends ConsumerStatefulWidget {
  const NpCandidateFormScreen({super.key, this.candidateId});

  /// Null ⇒ create.
  final int? candidateId;

  @override
  ConsumerState<NpCandidateFormScreen> createState() => _NpCandidateFormScreenState();
}

class _NpCandidateFormScreenState extends ConsumerState<NpCandidateFormScreen> {
  bool get _isEdit => widget.candidateId != null;

  final _c = <String, TextEditingController>{};
  TextEditingController _f(String k) => _c.putIfAbsent(k, () => TextEditingController());

  String? _gender;
  String? _maritalStatus;
  DateTime? _dob;
  DateTime? _spouseDob;
  bool _twoWheeler = false;
  bool _smartphone = false;
  bool _commSame = false;
  int? _branchId;
  Map<String, bool> _eligibility = {};
  int? _photoFileId;
  String? _photoUrl;

  bool _loading = false;
  bool _saving = false;
  bool _uploading = false;
  String? _error;

  // Aadhaar quick-fill
  final _aadhaar = TextEditingController();
  NpAadhaarLink? _aadhaarSession;
  String? _aadhaarBusy; // 'link' | 'fetch'
  String? _aadhaarStatus;
  bool _aadhaarVerified = false;

  // Bank verify
  bool _bankBusy = false;
  bool? _bankOk;
  String? _bankStatus;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _load();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    _aadhaar.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final c = await ref.read(npRepositoryProvider).candidate(widget.candidateId!);
      if (!mounted) return;
      if (!c.can('EDIT')) {
        npToast(context, 'This candidate can no longer be edited at its current stage.', error: true);
        context.pop();
        return;
      }
      _f('fullName').text = c.fullName;
      _f('mobile').text = c.mobileNumber;
      _f('altMobile').text = c.alternateMobile ?? '';
      _f('email').text = c.email ?? '';
      _f('father').text = c.fatherOrSpouseName ?? '';
      _f('spouseName').text = c.spouseName ?? '';
      _f('spouseMobile').text = c.spouseMobile ?? '';
      _f('spouseOcc').text = c.spouseOccupation ?? '';
      _f('addr').text = c.addressLine ?? '';
      _f('village').text = c.villageOrTown ?? '';
      _f('district').text = c.district ?? '';
      _f('state').text = c.state ?? '';
      _f('pin').text = c.pincode ?? '';
      _f('cAddr').text = c.commAddressLine ?? '';
      _f('cVillage').text = c.commVillageOrTown ?? '';
      _f('cDistrict').text = c.commDistrict ?? '';
      _f('cState').text = c.commState ?? '';
      _f('cPin').text = c.commPincode ?? '';
      _f('education').text = c.education ?? '';
      _f('occupation').text = c.occupation ?? '';
      _f('exp').text = c.experienceYears?.toString() ?? '';
      _f('aadhaar4').text = c.aadhaarLast4 ?? '';
      _f('pan').text = c.panNumber ?? '';
      _f('dl').text = c.drivingLicenceNumber ?? '';
      _f('bankName').text = c.bankName ?? '';
      _f('account').text = c.bankAccountNumber ?? '';
      _f('ifsc').text = c.bankIfsc ?? '';
      _f('holder').text = c.bankAccountHolderName ?? '';
      _f('eligNotes').text = c.eligibilityNotes ?? '';
      _f('remarks').text = c.remarks ?? '';
      setState(() {
        _gender = c.gender;
        _maritalStatus = c.maritalStatus;
        _dob = c.dateOfBirth;
        _spouseDob = c.spouseDateOfBirth;
        _twoWheeler = c.hasTwoWheeler ?? false;
        _smartphone = c.hasSmartphone ?? false;
        _branchId = c.branchId;
        _eligibility = Map.of(c.eligibility);
        _photoFileId = c.photo?.id;
        _photoUrl = Env.fileUrl(c.photo?.url);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copyPermanentToComm() {
    _f('cAddr').text = _f('addr').text;
    _f('cVillage').text = _f('village').text;
    _f('cDistrict').text = _f('district').text;
    _f('cState').text = _f('state').text;
    _f('cPin').text = _f('pin').text;
  }

  Future<void> _pickDate({required bool spouse}) async {
    final initial = (spouse ? _spouseDob : _dob) ?? DateTime(DateTime.now().year - 25);
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
    );
    if (d == null) return;
    setState(() => spouse ? _spouseDob = d : _dob = d);
  }

  Future<void> _pickPhoto() async {
    final picked = await npPickFile(context, imagesOnly: true);
    if (picked == null) return;
    await _uploadPhoto(picked.path, picked.name);
  }

  Future<void> _uploadPhoto(String path, String name) async {
    setState(() => _uploading = true);
    try {
      final f = await ref.read(fileRepositoryProvider).upload(path, filename: name);
      if (!mounted) return;
      setState(() {
        _photoFileId = f.id;
        _photoUrl = Env.fileUrl(f.url);
      });
    } catch (e) {
      if (mounted) npToast(context, 'Photo upload failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ── Aadhaar quick-fill ──

  Future<void> _aadhaarLink() async {
    final n = _aadhaar.text.trim();
    if (!RegExp(r'^\d{12}$').hasMatch(n)) {
      npToast(context, 'Enter the full 12-digit Aadhaar number.', error: true);
      return;
    }
    setState(() {
      _aadhaarBusy = 'link';
      _aadhaarVerified = false;
      _aadhaarStatus = null;
    });
    try {
      final s = await ref.read(npRepositoryProvider).startAadhaarLink(n);
      if (!mounted) return;
      setState(() => _aadhaarSession = s);
      final uri = Uri.tryParse(s.link);
      final opened = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (mounted) {
        setState(() => _aadhaarStatus = opened
            ? 'DigiLocker opened in the browser. Ask the candidate to complete consent there, then tap "Fetch details".'
            : 'Could not open the browser — use "Open DigiLocker", complete consent, then tap "Fetch details".');
      }
    } catch (e) {
      if (mounted) npToast(context, 'Could not start Aadhaar verification: $e', error: true);
    } finally {
      if (mounted) setState(() => _aadhaarBusy = null);
    }
  }

  Future<void> _aadhaarFetch() async {
    final s = _aadhaarSession;
    if (s == null) return;
    setState(() => _aadhaarBusy = 'fetch');
    try {
      final d = await ref.read(npRepositoryProvider).fetchAadhaarDetails(s.referenceId, s.transactionId);
      if (!mounted) return;
      if (!d.verified) {
        setState(() => _aadhaarStatus = d.message.isEmpty ? 'Aadhaar consent is not complete yet — finish it and try again.' : d.message);
        return;
      }
      void keep(String key, String? next) {
        if (next != null && next.trim().isNotEmpty) _f(key).text = next.trim();
      }
      keep('fullName', d.fullName);
      keep('father', d.fatherOrSpouseName);
      keep('addr', d.addressLine);
      keep('village', d.villageOrTown);
      keep('district', d.district);
      keep('state', d.state);
      keep('pin', d.pincode);
      _f('aadhaar4').text = d.aadhaarLast4 ?? _aadhaar.text.substring(8);
      setState(() {
        if (d.gender != null && kNpGenders.contains(d.gender!.toUpperCase())) _gender = d.gender!.toUpperCase();
        if (d.dateOfBirth != null) _dob = DateTime.tryParse(d.dateOfBirth!) ?? _dob;
        if (_commSame) _copyPermanentToComm();
      });
      if (d.photoBase64 != null && _photoFileId == null) await _uploadAadhaarPhoto(d.photoBase64!);
      if (!mounted) return;
      setState(() {
        _aadhaarVerified = true;
        _aadhaarStatus = 'Verified — details for ${d.fullName ?? 'the candidate'} filled in. Review them before saving.';
      });
      npToast(context, 'Candidate details filled from Aadhaar');
    } catch (e) {
      if (mounted) npToast(context, 'Could not fetch Aadhaar details: $e', error: true);
    } finally {
      if (mounted) setState(() => _aadhaarBusy = null);
    }
  }

  Future<void> _uploadAadhaarPhoto(String base64) async {
    try {
      final raw = base64.contains(',') ? base64.substring(base64.indexOf(',') + 1) : base64;
      final bytes = base64Decode(raw);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/aadhaar-photo-${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(bytes);
      await _uploadPhoto(file.path, 'aadhaar-photo.jpg');
    } catch (_) {
      if (mounted) npToast(context, 'Aadhaar photo could not be saved — upload one manually.', error: true);
    }
  }

  // ── Bank verify ──

  Future<void> _verifyBank() async {
    final account = _f('account').text.replaceAll(RegExp(r'\s'), '');
    final ifsc = _f('ifsc').text.trim().toUpperCase();
    if (account.length < 6) {
      npToast(context, 'Enter the bank account number first.', error: true);
      return;
    }
    if (!_ifscRe.hasMatch(ifsc)) {
      npToast(context, 'Enter a valid IFSC, e.g. SBIN0001234.', error: true);
      return;
    }
    setState(() {
      _bankBusy = true;
      _bankOk = null;
      _bankStatus = null;
    });
    try {
      final r = await ref.read(npRepositoryProvider).verifyBank(account, ifsc);
      if (!mounted) return;
      if (!r.verified) {
        setState(() {
          _bankOk = false;
          _bankStatus = r.message.isEmpty ? 'Bank verification failed.' : r.message;
        });
        return;
      }
      _f('account').text = account;
      _f('ifsc').text = r.ifsc ?? ifsc;
      if (r.accountHolderName != null && r.accountHolderName!.isNotEmpty) _f('holder').text = r.accountHolderName!;
      if (_f('bankName').text.trim().isEmpty && r.bankName != null) _f('bankName').text = r.bankName!;
      setState(() {
        _bankOk = true;
        _bankStatus = 'Verified — account held by ${r.accountHolderName ?? '—'}.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _bankOk = false;
          _bankStatus = '$e';
        });
      }
    } finally {
      if (mounted) setState(() => _bankBusy = false);
    }
  }

  // ── validate + save ──

  String? _validate() {
    final terms = Branding.current;
    if (_f('fullName').text.trim().isEmpty) return 'Full name is required.';
    if (!RegExp(r'^\d{10}$').hasMatch(_f('mobile').text.trim())) return 'Enter a valid 10-digit mobile number.';
    final alt = _f('altMobile').text.trim();
    if (alt.isNotEmpty && !RegExp(r'^\d{10}$').hasMatch(alt)) return 'The alternate mobile must be 10 digits.';
    final sm = _f('spouseMobile').text.trim();
    if (sm.isNotEmpty && !RegExp(r'^\d{10}$').hasMatch(sm)) return 'The spouse mobile must be 10 digits.';
    final pin = _f('pin').text.trim();
    if (pin.isNotEmpty && !RegExp(r'^\d{6}$').hasMatch(pin)) return 'The pincode must be 6 digits.';
    final cpin = _f('cPin').text.trim();
    if (cpin.isNotEmpty && !RegExp(r'^\d{6}$').hasMatch(cpin)) return 'The communication address pincode must be 6 digits.';
    final a4 = _f('aadhaar4').text.trim();
    if (a4.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(a4)) return 'Enter only the last 4 digits of the Aadhaar.';
    final pan = _f('pan').text.trim().toUpperCase();
    if (pan.isNotEmpty && !_panRe.hasMatch(pan)) return 'The PAN must look like ABCDE1234F.';
    if (_branchId == null || _branchId == 0) return 'Select a ${terms.term('branch').toLowerCase()}.';
    return null;
  }

  String? _blank(String key) {
    final v = _f(key).text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      npToast(context, problem, error: true);
      return;
    }
    if (_commSame) _copyPermanentToComm();
    setState(() {
      _error = null;
      _saving = true;
    });
    final input = NpCandidateInput()
      ..fullName = _f('fullName').text.trim()
      ..gender = _gender
      ..dateOfBirth = _dob == null ? null : npIsoDate(_dob!)
      ..mobileNumber = _f('mobile').text.trim()
      ..alternateMobile = _blank('altMobile')
      ..email = _blank('email')
      ..fatherOrSpouseName = _blank('father')
      ..maritalStatus = _maritalStatus
      ..spouseName = _blank('spouseName')
      ..spouseDateOfBirth = _spouseDob == null ? null : npIsoDate(_spouseDob!)
      ..spouseMobile = _blank('spouseMobile')
      ..spouseOccupation = _blank('spouseOcc')
      ..addressLine = _blank('addr')
      ..villageOrTown = _blank('village')
      ..district = _blank('district')
      ..state = _blank('state')
      ..pincode = _blank('pin')
      ..commAddressLine = _blank('cAddr')
      ..commVillageOrTown = _blank('cVillage')
      ..commDistrict = _blank('cDistrict')
      ..commState = _blank('cState')
      ..commPincode = _blank('cPin')
      ..education = _blank('education')
      ..occupation = _blank('occupation')
      ..experienceYears = int.tryParse(_f('exp').text.trim())
      ..hasTwoWheeler = _twoWheeler
      ..hasSmartphone = _smartphone
      ..aadhaarLast4 = _blank('aadhaar4')
      ..panNumber = _blank('pan')?.toUpperCase()
      ..drivingLicenceNumber = _blank('dl')
      ..bankAccountNumber = _blank('account')
      ..bankIfsc = _blank('ifsc')?.toUpperCase()
      ..bankName = _blank('bankName')
      ..bankAccountHolderName = _blank('holder')
      ..branchId = _branchId!
      ..eligibility = _eligibility
      ..eligibilityNotes = _blank('eligNotes')
      ..remarks = _blank('remarks')
      ..photoFileId = _photoFileId;
    try {
      final repo = ref.read(npRepositoryProvider);
      final saved = _isEdit ? await repo.update(widget.candidateId!, input) : await repo.create(input);
      if (!mounted) return;
      npToast(context, _isEdit ? 'Candidate updated' : 'Candidate created');
      if (_isEdit) {
        context.pop(true);
      } else {
        context.pushReplacement('/np/candidates/${saved.id}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
        npToast(context, '$e', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── render ──

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(npConfigProvider).asData?.value ?? NpConfig.empty;
    final branding = ref.watch(brandingProvider);
    final showSpouse = _maritalStatus != null && _maritalStatus != 'UNMARRIED';

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_isEdit ? 'Edit candidate' : 'New candidate'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  const Text(
                    "Capture the Prathinidhi's details. Saving creates a draft — submit it for identification from the candidate page.",
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  if (_error != null) ...[AppErrorPanel(message: _error!), const SizedBox(height: 12)],

                  if (config.aadhaarKycEnabled) _aadhaarSection(),

                  _section('Step 1', 'Identity', 'Who the candidate is.', [
                    const NpFieldLabel('Full name', required: true),
                    TextField(controller: _f('fullName'), textCapitalization: TextCapitalization.words, inputFormatters: const [TitleCaseTextFormatter()]),
                    const NpFieldLabel('Gender'),
                    _dropdown(_gender, kNpGenders, (v) => setState(() => _gender = v)),
                    const NpFieldLabel('Date of birth'),
                    _dateField(_dob, () => _pickDate(spouse: false)),
                    const NpFieldLabel("Father's name"),
                    TextField(controller: _f('father'), textCapitalization: TextCapitalization.words, inputFormatters: const [TitleCaseTextFormatter()]),
                    const _Hint('Sent to the credit bureau as a relation.'),
                    const NpFieldLabel('Marital status'),
                    _dropdown(_maritalStatus, kNpMaritalStatuses, (v) => setState(() => _maritalStatus = v)),
                    if (showSpouse) ...[
                      const NpFieldLabel('Spouse name'),
                      TextField(controller: _f('spouseName'), textCapitalization: TextCapitalization.words, inputFormatters: const [TitleCaseTextFormatter()]),
                      const NpFieldLabel('Spouse date of birth'),
                      _dateField(_spouseDob, () => _pickDate(spouse: true)),
                      const NpFieldLabel('Spouse mobile'),
                      _digits('spouseMobile', 10),
                      const NpFieldLabel('Spouse occupation'),
                      TextField(controller: _f('spouseOcc'), textCapitalization: TextCapitalization.words),
                    ],
                    const NpFieldLabel('Photo'),
                    Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 64,
                          height: 64,
                          color: AppColors.surfaceAlt,
                          child: _photoUrl == null
                              ? const Icon(Icons.person_rounded, color: AppColors.muted, size: 30)
                              : Image.network(_photoUrl!, fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _uploading ? null : _pickPhoto,
                          icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                          label: Text(_uploading ? 'Uploading…' : (_photoUrl == null ? 'Add photo' : 'Replace photo')),
                        ),
                      ),
                    ]),
                  ]),

                  _section('Step 2', 'Contact', 'How the branch reaches the candidate.', [
                    const NpFieldLabel('Mobile number', required: true),
                    _digits('mobile', 10),
                    const _Hint('10 digits — this number receives the activation OTP.'),
                    const NpFieldLabel('Alternate mobile'),
                    _digits('altMobile', 10),
                    const NpFieldLabel('Email'),
                    TextField(controller: _f('email'), keyboardType: TextInputType.emailAddress),
                  ]),

                  _section('Step 3', 'Address',
                      'Permanent address as per Aadhaar (used for the CB check and the BGV visit), and where the candidate can be reached.', [
                    const Text('Permanent address', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
                    const NpFieldLabel('Address line'),
                    TextField(controller: _f('addr'), textCapitalization: TextCapitalization.words, onChanged: (_) => _commSame ? _copyPermanentToComm() : null),
                    const NpFieldLabel('Village / town'),
                    TextField(controller: _f('village'), textCapitalization: TextCapitalization.words, onChanged: (_) => _commSame ? _copyPermanentToComm() : null),
                    const NpFieldLabel('District'),
                    TextField(controller: _f('district'), textCapitalization: TextCapitalization.words, onChanged: (_) => _commSame ? _copyPermanentToComm() : null),
                    const NpFieldLabel('State'),
                    TextField(controller: _f('state'), textCapitalization: TextCapitalization.words, onChanged: (_) => _commSame ? _copyPermanentToComm() : null),
                    const NpFieldLabel('Pincode'),
                    _digits('pin', 6, onChanged: (_) => _commSame ? _copyPermanentToComm() : null),
                    const SizedBox(height: 14),
                    Row(children: [
                      const Expanded(child: Text('Communication address', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink))),
                      const Text('Same', style: TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                      Switch(
                        value: _commSame,
                        onChanged: (v) => setState(() {
                          _commSame = v;
                          if (v) _copyPermanentToComm();
                        }),
                      ),
                    ]),
                    const NpFieldLabel('Address line'),
                    TextField(controller: _f('cAddr'), enabled: !_commSame, textCapitalization: TextCapitalization.words),
                    const NpFieldLabel('Village / town'),
                    TextField(controller: _f('cVillage'), enabled: !_commSame, textCapitalization: TextCapitalization.words),
                    const NpFieldLabel('District'),
                    TextField(controller: _f('cDistrict'), enabled: !_commSame, textCapitalization: TextCapitalization.words),
                    const NpFieldLabel('State'),
                    TextField(controller: _f('cState'), enabled: !_commSame, textCapitalization: TextCapitalization.words),
                    const NpFieldLabel('Pincode'),
                    _digits('cPin', 6, enabled: !_commSame),
                  ]),

                  _section('Step 4', 'Background', 'Education, work history and the tools the role needs.', [
                    const NpFieldLabel('Education'),
                    TextField(controller: _f('education'), textCapitalization: TextCapitalization.words),
                    const NpFieldLabel('Current occupation'),
                    TextField(controller: _f('occupation'), textCapitalization: TextCapitalization.words),
                    const NpFieldLabel('Experience (years)'),
                    _digits('exp', 2),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Owns a two-wheeler', style: TextStyle(fontSize: 13.5)),
                      value: _twoWheeler,
                      onChanged: (v) => setState(() => _twoWheeler = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Owns a smartphone', style: TextStyle(fontSize: 13.5)),
                      value: _smartphone,
                      onChanged: (v) => setState(() => _smartphone = v),
                    ),
                  ]),

                  _section('Step 5', 'Identity documents', 'Reference numbers only — the scans are uploaded at the KYC step.', [
                    const NpFieldLabel('Aadhaar (last 4 digits)'),
                    _digits('aadhaar4', 4),
                    const NpFieldLabel('PAN number'),
                    TextField(
                      controller: _f('pan'),
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [const UpperCaseTextFormatter(), LengthLimitingTextInputFormatter(10)],
                      decoration: const InputDecoration(hintText: 'ABCDE1234F'),
                    ),
                    const NpFieldLabel('Driving licence number'),
                    TextField(controller: _f('dl'), textCapitalization: TextCapitalization.characters, inputFormatters: const [UpperCaseTextFormatter()]),
                  ]),

                  _section('Step 6', 'Bank account', 'Optional at this stage; needed before the agreement.', [
                    const NpFieldLabel('Bank name'),
                    TextField(controller: _f('bankName'), textCapitalization: TextCapitalization.words),
                    const NpFieldLabel('Account number'),
                    TextField(
                      controller: _f('account'),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() => _bankStatus = null),
                    ),
                    const NpFieldLabel('IFSC'),
                    TextField(
                      controller: _f('ifsc'),
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [const UpperCaseTextFormatter(), LengthLimitingTextInputFormatter(11)],
                      onChanged: (_) => setState(() => _bankStatus = null),
                    ),
                    const NpFieldLabel('Name as per bank'),
                    TextField(controller: _f('holder'), textCapitalization: TextCapitalization.words),
                    const _Hint('Filled by bank verification; editable if the bank record differs.'),
                    if (config.bankVerifyEnabled) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _bankBusy ? null : _verifyBank,
                        icon: const Icon(Icons.account_balance_rounded, size: 18),
                        label: Text(_bankBusy ? 'Verifying…' : 'Verify bank account'),
                      ),
                      if (_bankStatus != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(_bankStatus!,
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _bankOk == true ? AppColors.success : AppColors.danger)),
                        ),
                    ],
                  ]),

                  _section('Step 7', 'Posting',
                      'The ${branding.term('branch').toLowerCase()} this Prathinidhi will work out of — it decides who can see and approve this file.', [
                    NpFieldLabel(branding.term('branch'), required: true),
                    ref.watch(_npBranchesProvider).when(
                          data: (branches) {
                            final ids = branches.map((b) => b.id).toSet();
                            final value = ids.contains(_branchId) ? _branchId : null;
                            return DropdownButtonFormField<int>(
                              value: value,
                              isExpanded: true,
                              hint: const Text('Select'),
                              items: [
                                for (final b in branches)
                                  DropdownMenuItem(
                                    value: b.id,
                                    child: Text(b.hierarchy.isEmpty ? b.label : '${b.label} · ${b.hierarchy}', overflow: TextOverflow.ellipsis),
                                  ),
                              ],
                              onChanged: (v) => setState(() => _branchId = v),
                            );
                          },
                          loading: () => const LinearProgressIndicator(minHeight: 2),
                          error: (e, _) => AppErrorPanel(message: 'Could not load branches: $e', onRetry: () => ref.invalidate(_npBranchesProvider)),
                        ),
                  ]),

                  _section('Step 8', 'Eligibility', 'Tick every criterion the candidate meets.', [
                    if (config.eligibilityCriteria.isEmpty)
                      const Text('No eligibility criteria are configured. Set them in Settings → NP Onboarding.',
                          style: TextStyle(fontSize: 12.5, color: AppColors.muted))
                    else
                      for (final c in config.eligibilityCriteria)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(c, style: const TextStyle(fontSize: 13.5)),
                          value: _eligibility[c] ?? false,
                          onChanged: (v) => setState(() => _eligibility[c] = v ?? false),
                        ),
                    const NpFieldLabel('Eligibility notes'),
                    TextField(controller: _f('eligNotes'), minLines: 2, maxLines: 4, textCapitalization: TextCapitalization.sentences),
                  ]),

                  _section('Step 9', 'Remarks', 'Anything the next reviewer should know.', [
                    TextField(controller: _f('remarks'), minLines: 3, maxLines: 6, textCapitalization: TextCapitalization.sentences),
                  ]),

                  if (_error != null) ...[AppErrorPanel(message: _error!), const SizedBox(height: 12)],
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: (_saving || _uploading) ? null : _save,
                      child: Text(_saving ? 'Saving…' : (_isEdit ? 'Save changes' : 'Create candidate')),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _aadhaarSection() {
    final busy = _aadhaarBusy != null;
    return _section('Quick fill', 'Fetch details from Aadhaar',
        'Verify through DigiLocker and the identity and address fields are filled from the Aadhaar record. Only the last 4 digits are stored.', [
      const NpFieldLabel('Aadhaar number'),
      TextField(
        controller: _aadhaar,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
        decoration: const InputDecoration(hintText: 'XXXX XXXX XXXX'),
        onChanged: (_) => setState(() {
          _aadhaarSession = null;
          _aadhaarVerified = false;
          _aadhaarStatus = null;
        }),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton(
          onPressed: (busy || _aadhaar.text.length != 12) ? null : _aadhaarLink,
          child: Text(_aadhaarBusy == 'link' ? 'Generating link…' : (_aadhaarSession == null ? 'Send DigiLocker link' : 'Resend DigiLocker link')),
        ),
        if (_aadhaarSession != null) ...[
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () {
                    final uri = Uri.tryParse(_aadhaarSession!.link);
                    if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Open DigiLocker'),
          ),
          FilledButton(
            onPressed: busy ? null : _aadhaarFetch,
            child: Text(_aadhaarBusy == 'fetch' ? 'Fetching…' : 'Fetch details'),
          ),
        ],
      ]),
      if (_aadhaarStatus != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_aadhaarStatus!,
              style: TextStyle(fontSize: 12.5, height: 1.4, color: _aadhaarVerified ? AppColors.success : AppColors.inkSoft, fontWeight: FontWeight.w500)),
        ),
    ]);
  }

  Widget _section(String eyebrow, String title, String description, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(eyebrow.toUpperCase(),
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.primary)),
            const SizedBox(height: 2),
            Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 2),
            Text(description, style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.35)),
            const Divider(height: 18, color: AppColors.hairline),
            ...children,
          ]),
        ),
      );

  Widget _dropdown(String? value, List<String> options, ValueChanged<String?> onChanged) => DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        hint: const Text('—'),
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('—')),
          for (final o in options) DropdownMenuItem(value: o, child: Text(npTitle(o))),
        ],
        onChanged: onChanged,
      );

  Widget _dateField(DateTime? value, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: InputDecorator(
          decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today_rounded, size: 18)),
          child: Text(value == null ? 'Not set' : npFmtDate(value),
              style: TextStyle(fontSize: 14, color: value == null ? AppColors.muted : AppColors.ink)),
        ),
      );

  Widget _digits(String key, int max, {bool enabled = true, ValueChanged<String>? onChanged}) => TextField(
        controller: _f(key),
        enabled: enabled,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(max)],
        onChanged: onChanged,
      );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(text, style: const TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.35)),
      );
}
