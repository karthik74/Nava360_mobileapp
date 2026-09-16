// ─────────────────────────────────────────────────────────────────────────────
//  NP Onboarding — the AM's background-verification visit report.
//  Route: /np/candidates/:id/bgv
//
//  Field flow: capture GPS at the residence → fill the visit findings → Save
//  draft (creates the report the photos attach to) → add the geotagged
//  residence + candidate photos → pick a recommendation → Submit BGV.
//  Server rule: submit needs GPS, both mandatory photos and a recommendation.
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

const _kResidencePhoto = 'RESIDENCE_PHOTO';
const _kCandidatePhoto = 'BGV_CANDIDATE_PHOTO';
const _kBgvPhotoTypes = {_kResidencePhoto, _kCandidatePhoto, 'BGV_SUPPORTING'};

class NpBgvScreen extends ConsumerStatefulWidget {
  const NpBgvScreen({super.key, required this.candidateId});
  final int candidateId;

  @override
  ConsumerState<NpBgvScreen> createState() => _NpBgvScreenState();
}

class _NpBgvScreenState extends ConsumerState<NpBgvScreen> {
  NpCandidateDetail? _d;
  bool _loading = true;
  bool _busy = false;
  bool _locating = false;
  String? _error;

  int? _draftId;
  DateTime _visitAt = DateTime.now();
  double? _lat, _lng, _accuracy;
  bool _addressVerified = false;
  final _addressAsFound = TextEditingController();
  String? _residenceType;
  final _years = TextEditingController();
  final List<_Member> _family = [];
  final _background = <String, TextEditingController>{for (final e in kNpBgvBackgroundKeys) e.key: TextEditingController()};
  final _checklist = <String, bool>{};
  final _amRemarks = TextEditingController();
  String? _recommendation;
  bool _seeded = false;

  int get _id => widget.candidateId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addressAsFound.dispose();
    _years.dispose();
    _amRemarks.dispose();
    for (final c in _background.values) {
      c.dispose();
    }
    for (final m in _family) {
      m.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _d == null;
      _error = null;
    });
    try {
      final d = await ref.read(npRepositoryProvider).candidate(_id);
      if (!mounted) return;
      setState(() => _d = d);
      final draft = d.bgvDraft;
      if (draft != null && !_seeded) {
        _seed(draft);
      }
      if (draft != null) _draftId = draft.id;
      _seeded = true;
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _seed(NpBgvReport r) {
    _draftId = r.id;
    if (r.visitAt != null) _visitAt = r.visitAt!;
    _lat = r.latitude;
    _lng = r.longitude;
    _accuracy = r.locationAccuracyM;
    _addressVerified = r.addressVerified ?? false;
    _addressAsFound.text = r.addressAsFound ?? '';
    _residenceType = r.residenceType;
    _years.text = r.yearsAtAddress?.toString() ?? '';
    for (final m in _family) {
      m.dispose();
    }
    _family
      ..clear()
      ..addAll(r.familyMembers.map(_Member.from));
    for (final e in r.background.entries) {
      _background.putIfAbsent(e.key, TextEditingController.new).text = e.value;
    }
    _checklist
      ..clear()
      ..addAll(r.checklist);
    _amRemarks.text = r.amRemarks ?? '';
    _recommendation = r.recommendation;
  }

  Future<void> _captureGps() async {
    setState(() => _locating = true);
    final loc = await npTryLocation();
    if (!mounted) return;
    setState(() => _locating = false);
    if (loc.lat == null || loc.lng == null) {
      npToast(context, 'Location unavailable — turn on GPS and allow location access.', error: true);
      return;
    }
    setState(() {
      _lat = loc.lat;
      _lng = loc.lng;
      _accuracy = loc.accuracy;
    });
    npToast(context, 'Location captured');
  }

  Future<void> _pickVisitAt() async {
    final d = await showDatePicker(context: context, initialDate: _visitAt, firstDate: DateTime(2020), lastDate: DateTime(2035));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_visitAt));
    if (t == null) return;
    setState(() => _visitAt = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  NpBgvDraftInput _input(List<String> checklistItems) => NpBgvDraftInput()
    ..visitAt = _visitAt
    ..latitude = _lat
    ..longitude = _lng
    ..locationAccuracyM = _accuracy
    ..addressVerified = _addressVerified
    ..addressAsFound = _addressAsFound.text.trim().isEmpty ? null : _addressAsFound.text.trim()
    ..residenceType = _residenceType
    ..yearsAtAddress = int.tryParse(_years.text.trim())
    ..familyMembers = _family.map((m) => m.toModel()).where((m) => m.name.isNotEmpty || m.relation.isNotEmpty).toList()
    ..background = {for (final e in _background.entries) if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim()}
    ..checklist = {for (final i in checklistItems) i: _checklist[i] == true}
    ..amRemarks = _amRemarks.text.trim().isEmpty ? null : _amRemarks.text.trim()
    ..recommendation = _recommendation;

  Future<bool> _saveDraft(List<String> checklistItems, {bool quiet = false}) async {
    setState(() => _busy = true);
    try {
      final saved = await ref.read(npRepositoryProvider).saveBgvDraft(_id, _input(checklistItems), reportId: _draftId);
      if (!mounted) return false;
      _draftId = saved.id;
      await _load();
      if (!quiet && mounted) npToast(context, 'BGV draft saved');
      return true;
    } catch (e) {
      if (mounted) npToast(context, 'Could not save the BGV draft: $e', error: true);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPhoto(NpConfig config, {String? type}) async {
    if (_draftId == null) {
      npToast(context, 'Save the draft first — photos attach to the saved report.', error: true);
      return;
    }
    final types = config.docTypesFor('BGV').where((t) => _kBgvPhotoTypes.contains(t.code)).toList();
    final ok = await npUploadDocumentSheet(
      context,
      ref,
      candidateId: _id,
      docTypes: types,
      initialDocType: type,
      captureGps: true,
      parentType: 'BGV_REPORT',
      parentId: _draftId,
    );
    if (ok) {
      await _load();
      if (mounted) npToast(context, 'Photo attached to the visit report');
    }
  }

  Future<void> _submit(List<String> checklistItems) async {
    // Persist the latest edits first so what the DM sees is what was typed.
    if (!await _saveDraft(checklistItems, quiet: true)) return;
    if (!mounted) return;
    if (!await npConfirm(context,
        title: 'Submit the BGV report?', message: 'It goes to the DM for approval and can no longer be edited.', confirmLabel: 'Submit')) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(npRepositoryProvider).submitBgv(_id, _draftId!);
      if (!mounted) return;
      npToast(context, 'BGV report submitted');
      context.pop(true);
    } catch (e) {
      if (mounted) npToast(context, 'BGV submission failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(npConfigProvider).asData?.value ?? NpConfig.empty;
    final d = _d;
    final draft = d?.bgvDraft;
    final photos = draft?.photos ?? const <NpDocument>[];
    final hasResidence = photos.any((p) => p.docType == _kResidencePhoto);
    final hasCandidate = photos.any((p) => p.docType == _kCandidatePhoto);
    final gps = _lat != null && _lng != null;
    final checklistItems = config.bgvChecklist.isNotEmpty ? config.bgvChecklist : _checklist.keys.toList();
    final canDraft = d?.can('BGV_DRAFT') ?? false;
    final canSubmit = (d?.can('BGV_SUBMIT') ?? false) && _draftId != null && gps && hasResidence && hasCandidate && _recommendation != null;

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('BGV visit report'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0.5,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : d == null
                ? Padding(padding: const EdgeInsets.all(16), child: AppErrorPanel(message: _error ?? 'Not found', onRetry: _load))
                : !canDraft
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: AppEmptyState(
                          icon: Icons.lock_outline_rounded,
                          message: 'The visit report cannot be edited at this stage (${d.statusLabel}).',
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        children: [
                          GlassCard(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(d.fullName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
                              Text('${d.candidateCode} · ${d.mobileNumber}', style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                              if (d.permanentAddress.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text('Address on file: ${d.permanentAddress}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                              ],
                            ]),
                          ),
                          const SizedBox(height: 10),
                          if (d.status == 'SENT_BACK_FOR_CORRECTION' && d.correctionRemarks != null) ...[
                            NpBanner(icon: Icons.undo_rounded, color: const Color(0xFFEA580C), title: 'Sent back — redo the visit', body: d.correctionRemarks),
                            const SizedBox(height: 10),
                          ],

                          // ── Progress ──
                          GlassCard(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('Before you can submit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
                              const SizedBox(height: 4),
                              NpCheckLine(ok: _draftId != null, label: 'Draft saved'),
                              NpCheckLine(ok: gps, label: 'GPS captured at the residence'),
                              NpCheckLine(ok: hasResidence, label: 'Residence photo'),
                              NpCheckLine(ok: hasCandidate, label: 'Candidate photo at the residence'),
                              NpCheckLine(ok: _recommendation != null, label: 'Recommendation picked'),
                            ]),
                          ),
                          const SizedBox(height: 10),

                          // ── Visit ──
                          _card('Visit', [
                            const NpFieldLabel('Visited at'),
                            InkWell(
                              onTap: _pickVisitAt,
                              borderRadius: BorderRadius.circular(AppRadii.md),
                              child: InputDecorator(
                                decoration: const InputDecoration(suffixIcon: Icon(Icons.schedule_rounded, size: 18)),
                                child: Text(npFmtDateTime(_visitAt), style: const TextStyle(fontSize: 14, color: AppColors.ink)),
                              ),
                            ),
                            const NpFieldLabel('GPS location', required: true),
                            Row(children: [
                              OutlinedButton.icon(
                                onPressed: (_locating || _busy) ? null : _captureGps,
                                icon: _locating
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.my_location_rounded, size: 18),
                                label: Text(_locating ? 'Locating…' : (gps ? 'Recapture' : 'Capture GPS')),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: gps
                                    ? InkWell(
                                        onTap: () => npOpenMaps(_lat!, _lng!),
                                        child: Text(
                                          '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}${_accuracy != null ? ' (±${_accuracy!.round()} m)' : ''}',
                                          style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
                                        ),
                                      )
                                    : const Text('Not captured', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                              ),
                            ]),
                            const NpFieldLabel('Residence type'),
                            DropdownButtonFormField<String>(
                              value: _residenceType,
                              hint: const Text('—'),
                              items: [for (final t in kNpResidenceTypes) DropdownMenuItem(value: t, child: Text(npTitle(t)))],
                              onChanged: (v) => setState(() => _residenceType = v),
                            ),
                            const NpFieldLabel('Years at address'),
                            TextField(
                              controller: _years,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                            ),
                            const NpFieldLabel('Address as found'),
                            TextField(controller: _addressAsFound, minLines: 1, maxLines: 3, textCapitalization: TextCapitalization.words),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: const Text('Address verified', style: TextStyle(fontSize: 13.5)),
                              value: _addressVerified,
                              onChanged: (v) => setState(() => _addressVerified = v),
                            ),
                          ]),

                          // ── Family ──
                          _card('Family members', [
                            if (_family.isEmpty)
                              const Text('None recorded.', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
                            for (var i = 0; i < _family.length; i++)
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceAlt,
                                  borderRadius: BorderRadius.circular(AppRadii.md),
                                  border: Border.all(color: AppColors.hairline),
                                ),
                                child: Column(children: [
                                  Row(children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _family[i].name,
                                        textCapitalization: TextCapitalization.words,
                                        inputFormatters: const [TitleCaseTextFormatter()],
                                        decoration: const InputDecoration(hintText: 'Name'),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => setState(() => _family.removeAt(i).dispose()),
                                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                                    ),
                                  ]),
                                  const SizedBox(height: 6),
                                  Row(children: [
                                    Expanded(
                                      flex: 3,
                                      child: TextField(
                                        controller: _family[i].relation,
                                        textCapitalization: TextCapitalization.words,
                                        decoration: const InputDecoration(hintText: 'Relation'),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      flex: 2,
                                      child: TextField(
                                        controller: _family[i].age,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                                        decoration: const InputDecoration(hintText: 'Age'),
                                      ),
                                    ),
                                  ]),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _family[i].occupation,
                                    textCapitalization: TextCapitalization.words,
                                    decoration: const InputDecoration(hintText: 'Occupation'),
                                  ),
                                ]),
                              ),
                            OutlinedButton.icon(
                              onPressed: () => setState(() => _family.add(_Member())),
                              icon: const Icon(Icons.person_add_alt_rounded, size: 18),
                              label: const Text('Add member'),
                            ),
                          ]),

                          // ── Background ──
                          _card('Background observations', [
                            for (final e in kNpBgvBackgroundKeys) ...[
                              NpFieldLabel(e.value),
                              TextField(controller: _background[e.key], minLines: 1, maxLines: 3, textCapitalization: TextCapitalization.sentences),
                            ],
                          ]),

                          // ── Checklist ──
                          _card('Checklist', [
                            if (checklistItems.isEmpty)
                              const Text('No checklist configured.', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
                            for (final item in checklistItems)
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                controlAffinity: ListTileControlAffinity.leading,
                                title: Text(item, style: const TextStyle(fontSize: 13.5)),
                                value: _checklist[item] ?? false,
                                onChanged: (v) => setState(() => _checklist[item] = v ?? false),
                              ),
                          ]),

                          // ── Remarks + recommendation ──
                          _card('Assessment', [
                            const NpFieldLabel('AM remarks'),
                            TextField(controller: _amRemarks, minLines: 2, maxLines: 5, textCapitalization: TextCapitalization.sentences),
                            const NpFieldLabel('Recommendation', required: true),
                            DropdownButtonFormField<String>(
                              value: _recommendation,
                              hint: const Text('—'),
                              items: const [
                                DropdownMenuItem(value: 'RECOMMENDED', child: Text('Recommended')),
                                DropdownMenuItem(value: 'NOT_RECOMMENDED', child: Text('Not recommended')),
                              ],
                              onChanged: (v) => setState(() => _recommendation = v),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : () => _saveDraft(checklistItems),
                              icon: const Icon(Icons.save_outlined, size: 18),
                              label: Text(_draftId == null ? 'Save draft' : 'Save draft changes'),
                            ),
                          ]),

                          // ── Photos ──
                          _card('Visit photos', [
                            Text(
                              _draftId == null
                                  ? 'Save the draft first — photos attach to the saved report.'
                                  : 'Each photo is geotagged with your current location.',
                              style: const TextStyle(fontSize: 12, color: AppColors.muted),
                            ),
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              OutlinedButton.icon(
                                onPressed: (_busy || _draftId == null) ? null : () => _addPhoto(config, type: _kResidencePhoto),
                                icon: Icon(hasResidence ? Icons.check_circle_rounded : Icons.home_rounded, size: 18, color: hasResidence ? AppColors.success : null),
                                label: const Text('Residence photo'),
                              ),
                              OutlinedButton.icon(
                                onPressed: (_busy || _draftId == null) ? null : () => _addPhoto(config, type: _kCandidatePhoto),
                                icon: Icon(hasCandidate ? Icons.check_circle_rounded : Icons.person_pin_rounded, size: 18, color: hasCandidate ? AppColors.success : null),
                                label: const Text('Candidate photo'),
                              ),
                              OutlinedButton.icon(
                                onPressed: (_busy || _draftId == null) ? null : () => _addPhoto(config, type: 'BGV_SUPPORTING'),
                                icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                                label: const Text('Supporting'),
                              ),
                            ]),
                            const SizedBox(height: 10),
                            NpDocumentList(documents: photos, emptyText: 'No photos on this draft yet.'),
                            if (_draftId != null && (!hasResidence || !hasCandidate))
                              Text(
                                'Still needed: ${[if (!hasResidence) 'residence photo', if (!hasCandidate) 'candidate photo'].join(' and ')}.',
                                style: const TextStyle(fontSize: 12, color: AppColors.warning, fontWeight: FontWeight.w600),
                              ),
                          ]),

                          SizedBox(
                            height: 50,
                            child: FilledButton.icon(
                              onPressed: (_busy || !canSubmit) ? null : () => _submit(checklistItems),
                              icon: const Icon(Icons.send_rounded, size: 18),
                              label: const Text('Submit BGV report'),
                            ),
                          ),
                          if (!canSubmit)
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text('Save the draft, capture GPS, add both required photos and pick a recommendation first.',
                                  textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                            ),
                        ],
                      ),
      ),
    );
  }

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

class _Member {
  final name = TextEditingController();
  final relation = TextEditingController();
  final age = TextEditingController();
  final occupation = TextEditingController();

  _Member();

  factory _Member.from(NpFamilyMember m) => _Member()
    ..name.text = m.name
    ..relation.text = m.relation
    ..age.text = m.age?.toString() ?? ''
    ..occupation.text = m.occupation ?? '';

  NpFamilyMember toModel() => NpFamilyMember(
        name: name.text.trim(),
        relation: relation.text.trim(),
        age: int.tryParse(age.text.trim()),
        occupation: occupation.text.trim().isEmpty ? null : occupation.text.trim(),
      );

  void dispose() {
    name.dispose();
    relation.dispose();
    age.dispose();
    occupation.dispose();
  }
}
