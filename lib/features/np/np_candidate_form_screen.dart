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
import '../../core/pro_ui.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../files/file_repository.dart';
import '../requisitions/requisition_models.dart';
import '../requisitions/requisition_repository.dart';
import 'np_aadhaar.dart';
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

  // Masked numbers already on file (edit) — the full numbers never come back to the app.
  String? _aadhaarOnFile;
  String? _spouseAadhaarOnFile;

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
    _scroll.dispose();
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
      _f('spouseFather').text = c.spouseFatherName ?? '';
      _f('spousePan').text = c.spousePanNumber ?? '';
      _f('spouseDl').text = c.spouseDrivingLicenceNumber ?? '';
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
        _aadhaarOnFile = c.aadhaarMasked;
        _spouseAadhaarOnFile = c.spouseAadhaarMasked;
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
      _f('aadhaarFull').text = _aadhaar.text.trim();
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
    // Everything the credit bureau needs is mandatory.
    bool empty(String key) => _f(key).text.trim().isEmpty;
    final missing = <String>[
      if (_gender == null) 'gender',
      if (_dob == null) 'date of birth',
      if (empty('father')) "father's name",
      if (_maritalStatus == null) 'marital status',
      if (empty('aadhaarFull') && _aadhaarOnFile == null) 'Aadhaar number',
      if (empty('addr')) 'address',
      if (empty('village')) 'village / town',
      if (empty('district')) 'district',
      if (empty('state')) 'state',
      if (empty('pin')) 'pincode',
      if (_spouseRequired) ...[
        if (empty('spouseName')) 'spouse name',
        if (_spouseDob == null) 'spouse date of birth',
        if (empty('spouseFather')) "spouse's father's name",
        if (empty('spouseAadhaarFull') && _spouseAadhaarOnFile == null) 'spouse Aadhaar number',
      ],
    ];
    if (missing.isNotEmpty) return 'Required for the credit bureau check: ${missing.join(', ')}.';
    final aadhaar = _f('aadhaarFull').text.trim();
    if (aadhaar.isNotEmpty && !isValidAadhaar(aadhaar)) return 'The Aadhaar number is not valid — check all 12 digits.';
    final spouseAadhaar = _f('spouseAadhaarFull').text.trim();
    if (_spouseRequired && spouseAadhaar.isNotEmpty) {
      if (!isValidAadhaar(spouseAadhaar)) return "The spouse's Aadhaar number is not valid — check all 12 digits.";
      if (spouseAadhaar == aadhaar) return "The spouse's Aadhaar number cannot be the candidate's own.";
    }
    final alt = _f('altMobile').text.trim();
    if (alt.isNotEmpty && !RegExp(r'^\d{10}$').hasMatch(alt)) return 'The alternate mobile must be 10 digits.';
    final sm = _f('spouseMobile').text.trim();
    if (sm.isNotEmpty && !RegExp(r'^\d{10}$').hasMatch(sm)) return 'The spouse mobile must be 10 digits.';
    final pin = _f('pin').text.trim();
    if (pin.isNotEmpty && !RegExp(r'^\d{6}$').hasMatch(pin)) return 'The pincode must be 6 digits.';
    final cpin = _f('cPin').text.trim();
    if (cpin.isNotEmpty && !RegExp(r'^\d{6}$').hasMatch(cpin)) return 'The communication address pincode must be 6 digits.';
    final pan = _f('pan').text.trim().toUpperCase();
    if (pan.isNotEmpty && !_panRe.hasMatch(pan)) return 'The PAN must look like ABCDE1234F.';
    final spousePan = _f('spousePan').text.trim().toUpperCase();
    if (spousePan.isNotEmpty && !_panRe.hasMatch(spousePan)) return 'The spouse PAN must look like ABCDE1234F.';
    if (_branchId == null || _branchId == 0) return 'Select a ${terms.term('branch').toLowerCase()}.';
    return null;
  }

  /// A married candidate's spouse is credit-checked too, so their identity is mandatory.
  bool get _spouseRequired => _maritalStatus == 'MARRIED';

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
      ..spouseFatherName = _blank('spouseFather')
      ..spouseAadhaarNumber = _spouseRequired ? _blank('spouseAadhaarFull') : null
      ..spousePanNumber = _blank('spousePan')?.toUpperCase()
      ..spouseDrivingLicenceNumber = _blank('spouseDl')
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
      ..aadhaarNumber = _blank('aadhaarFull')
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

  /// Wizard position — purely presentational: every field stays in state
  /// and [_validate] / [_save] still check the whole form at once.
  int _step = 0;
  final _scroll = ScrollController();

  void _goTo(int i) {
    FocusScope.of(context).unfocus();
    setState(() => _step = i);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  Future<void> _saveAndReveal() async {
    await _save();
    if (mounted && _error != null && _scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(npConfigProvider).asData?.value ?? NpConfig.empty;
    final branding = ref.watch(brandingProvider);
    final showSpouse = _maritalStatus != null && _maritalStatus != 'UNMARRIED';

    final steps = <_FormStep>[
      _FormStep('Identity', 'Identity', 'Who the candidate is.', [
        _field('Full name', required: true,
            TextField(controller: _f('fullName'), textCapitalization: TextCapitalization.words, inputFormatters: const [TitleCaseTextFormatter()])),
        _field('Gender', required: true, _dropdown(_gender, kNpGenders, (v) => setState(() => _gender = v))),
        _field('Date of birth', required: true, _dateField(_dob, () => _pickDate(spouse: false))),
        _field("Father's name",
            required: true,
            hint: 'Sent to the credit bureau as a relation.',
            TextField(controller: _f('father'), textCapitalization: TextCapitalization.words, inputFormatters: const [TitleCaseTextFormatter()])),
        _field('Marital status', required: true, _dropdown(_maritalStatus, kNpMaritalStatuses, (v) => setState(() => _maritalStatus = v))),
        if (showSpouse) ...[
          _subhead('Spouse'),
          _field('Spouse name',
              required: _spouseRequired,
              TextField(controller: _f('spouseName'), textCapitalization: TextCapitalization.words, inputFormatters: const [TitleCaseTextFormatter()])),
          _field('Spouse date of birth', required: _spouseRequired, _dateField(_spouseDob, () => _pickDate(spouse: true))),
          _field('Spouse mobile', _digits('spouseMobile', 10)),
          _field('Spouse occupation', TextField(controller: _f('spouseOcc'), textCapitalization: TextCapitalization.words)),
          _field("Spouse's father's name",
              required: _spouseRequired,
              hint: "Sent to the credit bureau as the spouse's relation.",
              TextField(controller: _f('spouseFather'), textCapitalization: TextCapitalization.words, inputFormatters: const [TitleCaseTextFormatter()])),
          _field('Spouse Aadhaar number',
              required: _spouseRequired && _spouseAadhaarOnFile == null,
              hint: _spouseAadhaarOnFile != null
                  ? 'On file: $_spouseAadhaarOnFile — leave blank to keep it.'
                  : 'All 12 digits — sent to the credit bureau.',
              _aadhaarField('spouseAadhaarFull', _spouseAadhaarOnFile)),
          _field('Spouse PAN',
              hint: 'Optional — sent to the credit bureau with the Aadhaar.',
              TextField(
                controller: _f('spousePan'),
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [const UpperCaseTextFormatter(), LengthLimitingTextInputFormatter(10)],
              )),
          _field('Spouse driving licence',
              TextField(controller: _f('spouseDl'), textCapitalization: TextCapitalization.characters, inputFormatters: const [UpperCaseTextFormatter()])),
        ],
        _field(
          'Photo',
          Row(children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.neutralTint,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.hairline),
              ),
              clipBehavior: Clip.antiAlias,
              child: _photoUrl == null
                  ? const Icon(Icons.person_outline_rounded, color: AppColors.faint, size: 30)
                  : Image.network(_photoUrl!, fit: BoxFit.cover),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _uploading ? null : _pickPhoto,
                icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                label: Text(_uploading ? 'Uploading…' : (_photoUrl == null ? 'Add photo' : 'Replace photo')),
              ),
            ),
          ]),
        ),
      ]),
      _FormStep('Contact', 'Contact', 'How the branch reaches the candidate.', [
        _field('Mobile number', required: true, hint: '10 digits — this number receives the activation OTP.', _digits('mobile', 10)),
        _field('Alternate mobile', _digits('altMobile', 10)),
        _field('Email', TextField(controller: _f('email'), keyboardType: TextInputType.emailAddress)),
      ]),
      _FormStep('Address', 'Address',
          'Permanent address as per Aadhaar (used for the CB check and the BGV visit), and where the candidate can be reached.', [
        _subhead('Permanent address'),
        _field('Address line',
            required: true,
            TextField(controller: _f('addr'), textCapitalization: TextCapitalization.words, onChanged: (_) => _commSame ? _copyPermanentToComm() : null)),
        _field('Village / town',
            required: true,
            TextField(controller: _f('village'), textCapitalization: TextCapitalization.words, onChanged: (_) => _commSame ? _copyPermanentToComm() : null)),
        _field('District',
            required: true,
            TextField(controller: _f('district'), textCapitalization: TextCapitalization.words, onChanged: (_) => _commSame ? _copyPermanentToComm() : null)),
        _field('State',
            required: true,
            TextField(controller: _f('state'), textCapitalization: TextCapitalization.words, onChanged: (_) => _commSame ? _copyPermanentToComm() : null)),
        _field('Pincode', required: true, _digits('pin', 6, onChanged: (_) => _commSame ? _copyPermanentToComm() : null)),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Row(children: [
            const Expanded(child: Text('Communication address', style: _subheadStyle)),
            const Text('Same as permanent', style: TextStyle(fontSize: 13, color: AppColors.muted)),
            const SizedBox(width: 6),
            Switch(
              value: _commSame,
              onChanged: (v) => setState(() {
                _commSame = v;
                if (v) _copyPermanentToComm();
              }),
            ),
          ]),
        ),
        _field('Address line', TextField(controller: _f('cAddr'), enabled: !_commSame, textCapitalization: TextCapitalization.words)),
        _field('Village / town', TextField(controller: _f('cVillage'), enabled: !_commSame, textCapitalization: TextCapitalization.words)),
        _field('District', TextField(controller: _f('cDistrict'), enabled: !_commSame, textCapitalization: TextCapitalization.words)),
        _field('State', TextField(controller: _f('cState'), enabled: !_commSame, textCapitalization: TextCapitalization.words)),
        _field('Pincode', _digits('cPin', 6, enabled: !_commSame)),
      ]),
      _FormStep('Background', 'Background', 'Education, work history and the tools the role needs.', [
        _field('Education', TextField(controller: _f('education'), textCapitalization: TextCapitalization.words)),
        _field('Current occupation', TextField(controller: _f('occupation'), textCapitalization: TextCapitalization.words)),
        _field('Experience (years)', _digits('exp', 2)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Owns a two-wheeler', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
          value: _twoWheeler,
          onChanged: (v) => setState(() => _twoWheeler = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Owns a smartphone', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
          value: _smartphone,
          onChanged: (v) => setState(() => _smartphone = v),
        ),
      ]),
      _FormStep('Documents', 'Identity documents', 'Reference numbers only — the scans are uploaded at the KYC step.', [
        _field('Aadhaar number',
            required: _aadhaarOnFile == null,
            hint: _aadhaarOnFile != null
                ? 'On file: $_aadhaarOnFile — leave blank to keep it.'
                : 'All 12 digits — stored encrypted and sent to the credit bureau.',
            _aadhaarField('aadhaarFull', _aadhaarOnFile)),
        _field('PAN number',
            TextField(
              controller: _f('pan'),
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [const UpperCaseTextFormatter(), LengthLimitingTextInputFormatter(10)],
              decoration: const InputDecoration(hintText: 'ABCDE1234F'),
            )),
        _field('Driving licence number',
            TextField(controller: _f('dl'), textCapitalization: TextCapitalization.characters, inputFormatters: const [UpperCaseTextFormatter()])),
      ]),
      _FormStep('Bank', 'Bank account', 'Optional at this stage; needed before the agreement.', [
        _field('Bank name', TextField(controller: _f('bankName'), textCapitalization: TextCapitalization.words)),
        _field('Account number',
            TextField(
              controller: _f('account'),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() => _bankStatus = null),
            )),
        _field('IFSC',
            TextField(
              controller: _f('ifsc'),
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [const UpperCaseTextFormatter(), LengthLimitingTextInputFormatter(11)],
              onChanged: (_) => setState(() => _bankStatus = null),
            )),
        _field('Name as per bank',
            hint: 'Filled by bank verification; editable if the bank record differs.',
            TextField(controller: _f('holder'), textCapitalization: TextCapitalization.words)),
        if (config.bankVerifyEnabled) ...[
          OutlinedButton.icon(
            onPressed: _bankBusy ? null : _verifyBank,
            icon: const Icon(Icons.account_balance_outlined, size: 18),
            label: Text(_bankBusy ? 'Verifying…' : 'Verify bank account'),
          ),
          if (_bankStatus != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: ProNote(_bankStatus!, tone: _bankOk == true ? ProNoteTone.ok : ProNoteTone.bad),
            ),
        ],
      ]),
      _FormStep('Posting', 'Posting',
          'The ${branding.term('branch').toLowerCase()} this Prathinidhi will work out of — it decides who can see and approve this file.', [
        _field(
          branding.term('branch'),
          required: true,
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
        ),
      ]),
      _FormStep('Eligibility', 'Eligibility', 'Tick every criterion the candidate meets.', [
        if (config.eligibilityCriteria.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: ProNote('No eligibility criteria are configured. Set them in Settings → NP Onboarding.'),
          )
        else
          for (final c in config.eligibilityCriteria)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(c, style: const TextStyle(fontSize: 14.5)),
              value: _eligibility[c] ?? false,
              onChanged: (v) => setState(() => _eligibility[c] = v ?? false),
            ),
        const SizedBox(height: 6),
        _field('Eligibility notes', TextField(controller: _f('eligNotes'), minLines: 2, maxLines: 4, textCapitalization: TextCapitalization.sentences)),
      ]),
      _FormStep('Remarks', 'Remarks', 'Anything the next reviewer should know.', [
        TextField(controller: _f('remarks'), minLines: 3, maxLines: 6, textCapitalization: TextCapitalization.sentences),
      ]),
    ];

    final last = steps.length - 1;
    final cur = _step.clamp(0, last);
    final step = steps[cur];
    final busy = _saving || _uploading;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: proLightAppBar(
        context,
        title: _isEdit ? 'Edit candidate' : 'New candidate',
        subtitle: 'Step ${cur + 1} of ${steps.length} · ${step.title}',
        actions: [
          if (_isEdit && !_loading && cur < last)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(onPressed: busy ? null : _saveAndReveal, child: Text(_saving ? 'Saving…' : 'Save')),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                ProStepBar(total: steps.length, current: cur),
                const SizedBox(height: 12),
                ProChipBar(labels: [for (final s in steps) s.short], selected: cur, onSelected: _goTo, bleed: 0),
                const SizedBox(height: 14),
                const ProNote(
                  "Capture the Prathinidhi's details. Saving creates a draft — submit it for identification from the candidate page.",
                  tone: ProNoteTone.info,
                ),
                const SizedBox(height: 14),
                if (_error != null) ...[AppErrorPanel(message: _error!), const SizedBox(height: 14)],
                if (cur == 0 && config.aadhaarKycEnabled) ...[_aadhaarSection(), const SizedBox(height: 14)],
                _section('Step ${cur + 1}', step.title, step.description, step.children),
              ],
            ),
      bottomNavigationBar: _loading
          ? null
          : ProBottomBar(children: [
              if (cur == 0)
                OutlinedButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Cancel'))
              else
                OutlinedButton.icon(
                  onPressed: () => _goTo(cur - 1),
                  icon: const Icon(Icons.chevron_left_rounded, size: 20),
                  label: const Text('Back'),
                ),
              if (cur < last)
                FilledButton(
                  onPressed: () => _goTo(cur + 1),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Next'),
                    SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, size: 20),
                  ]),
                )
              else
                FilledButton(
                  onPressed: busy ? null : _saveAndReveal,
                  child: Text(_saving ? 'Saving…' : (_isEdit ? 'Save changes' : 'Create candidate')),
                ),
            ]),
    );
  }

  Widget _aadhaarSection() {
    final busy = _aadhaarBusy != null;
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          ProIconWell(icon: Icons.fingerprint_rounded, color: AppColors.primary, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Quick fill', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.primary)),
              const Text('Fetch details from Aadhaar', style: AppText.section),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        const Text(
          'Verify through DigiLocker and the identity and address fields are filled from the Aadhaar record. Only the last 4 digits are stored.',
          style: AppText.caption,
        ),
        const SizedBox(height: 14),
        _field(
          'Aadhaar number',
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
        ),
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
            padding: const EdgeInsets.only(top: 12),
            child: ProNote(_aadhaarStatus!, tone: _aadhaarVerified ? ProNoteTone.ok : ProNoteTone.info),
          ),
      ]),
    );
  }

  Widget _section(String eyebrow, String title, String description, List<Widget> children) => GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title, style: AppText.title)),
            ProPill.neutral(eyebrow),
          ]),
          const SizedBox(height: 3),
          Text(description, style: AppText.caption),
          const SizedBox(height: 16),
          ...children,
        ]),
      );

  static const _subheadStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink);

  Widget _subhead(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text, style: _subheadStyle),
      );

  /// Label above, field, optional helper below (Pro form rhythm).
  Widget _field(String label, Widget child, {bool required = false, String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: ProField(label: label, required: required, helper: hint, child: child),
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
          decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today_outlined, size: 18)),
          child: Text(value == null ? 'Not set' : npFmtDate(value),
              style: TextStyle(fontSize: 15, color: value == null ? AppColors.muted : AppColors.ink)),
        ),
      );

  Widget _aadhaarField(String key, String? onFile) => TextField(
        controller: _f(key),
        keyboardType: TextInputType.number,
        autocorrect: false,
        enableSuggestions: false,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
        decoration: InputDecoration(hintText: onFile ?? '12 digits'),
      );

  Widget _digits(String key, int max, {bool enabled = true, ValueChanged<String>? onChanged}) => TextField(
        controller: _f(key),
        enabled: enabled,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(max)],
        onChanged: onChanged,
      );
}

/// One wizard page of the candidate form.
class _FormStep {
  const _FormStep(this.short, this.title, this.description, this.children);
  final String short;
  final String title;
  final String description;
  final List<Widget> children;
}
