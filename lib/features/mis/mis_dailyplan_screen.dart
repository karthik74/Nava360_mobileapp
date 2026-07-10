// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Daily Plan (route /mis/daily-plan). The branch daily plan / achievement
//  ENTRY form — a BM submits for their own branch (pinned to today); an AM (or
//  wider) picks a branch and may back-fill past dates. Pre-fills from
//  /daily-plan/mine and POSTs to /daily-plan/save. Ports DailyPlanForm.tsx.
//
//  The manager report builder / pending-branches / flat report table (read-only
//  report generators in DailyPlanScreen.tsx) are not ported here — this is the
//  write surface.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_auth.dart';
import 'mis_models.dart';
import 'mis_repository.dart';
import 'mis_widgets.dart';

const _fields = [
  'ftod_actual', 'ftod_plan',
  'dpd_1_30_actual', 'dpd_1_30_plan',
  'dpd_31_60_actual', 'dpd_31_60_plan',
  'dpd_61_90_actual', 'dpd_61_90_plan',
  'fy_non_start_acc', 'fy_non_start_plan',
  'disb_igl_acc', 'disb_igl_amt',
  'disb_fig_acc', 'disb_fig_amt',
  'disb_il_acc', 'disb_il_amt',
  'kyc_igl', 'kyc_fig', 'kyc_il',
  'npa_activation', 'npa_closure',
];

const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mo = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _pad(int n) => n < 10 ? '0$n' : '$n';
String _iso(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';
String _todayIso() => _iso(DateTime.now());
String _shiftIso(String iso, int delta) {
  final p = iso.split('-');
  final d = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]))
      .add(Duration(days: delta));
  return _iso(d);
}

String _prettyDay(String iso) {
  final p = iso.split('-');
  if (p.length < 3) return iso;
  final d = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  return '${_wd[d.weekday - 1]}, ${_pad(d.day)} ${_mo[d.month - 1]} ${d.year}';
}

String _s(double v) => v == 0
    ? ''
    : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

class MisDailyPlanScreen extends ConsumerStatefulWidget {
  const MisDailyPlanScreen({super.key});

  @override
  ConsumerState<MisDailyPlanScreen> createState() =>
      _MisDailyPlanScreenState();
}

class _MisDailyPlanScreenState extends ConsumerState<MisDailyPlanScreen> {
  late final Map<String, TextEditingController> _c = {
    for (final k in _fields) k: TextEditingController(),
  };

  String? _fixedBranch; // BM: their own branch
  bool _pickerMode = false; // AM+ : branch selector + past-date editing
  List<DailyPlanBranch> _branches = const [];
  String? _branch; // picker selection

  String _date = _todayIso();
  String _type = 'plan'; // plan | achievement

  DailyPlanMine? _plan, _ach, _yPlan, _yAch;
  bool _loading = true;
  bool _busy = false;
  (bool, String)? _msg; // (ok, text)

  @override
  void initState() {
    super.initState();
    final user = ref.read(misSessionProvider)?.user;
    _fixedBranch = user?.branch;
    _pickerMode = _fixedBranch == null || _fixedBranch!.isEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    for (final ctl in _c.values) {
      ctl.dispose();
    }
    super.dispose();
  }

  String? get _activeBranch => _pickerMode ? _branch : _fixedBranch;

  Future<void> _init() async {
    if (_pickerMode) {
      try {
        final branches = await ref.read(misRepositoryProvider).dailyPlanBranches();
        if (!mounted) return;
        setState(() {
          _branches = branches;
          _branch = branches.isNotEmpty ? branches.first.branchName : null;
        });
      } catch (_) {}
    }
    await _load();
  }

  Future<void> _load() async {
    final br = _pickerMode ? _branch : null;
    if (_activeBranch == null || _activeBranch!.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final repo = ref.read(misRepositoryProvider);
    final y = _shiftIso(_date, -1);
    try {
      final res = await Future.wait([
        repo.dailyPlanMine(_date, 'plan', br),
        repo.dailyPlanMine(_date, 'achievement', br),
        repo.dailyPlanMine(y, 'plan', br),
        repo.dailyPlanMine(y, 'achievement', br),
      ]);
      _plan = res[0];
      _ach = res[1];
      _yPlan = res[2];
      _yAch = res[3];
    } catch (_) {
      _plan = _ach = _yPlan = _yAch = null;
    }
    if (!mounted) return;
    setState(() => _loading = false);
    _apply(_type == 'plan' ? _plan : _ach);
  }

  void _apply(DailyPlanMine? d) {
    final m = <String, String>{};
    if (d != null && d.exists) {
      m['ftod_actual'] = _s(d.ftod.actual);
      m['ftod_plan'] = _s(d.ftod.plan);
      m['dpd_1_30_actual'] = _s(d.dpd130.actual);
      m['dpd_1_30_plan'] = _s(d.dpd130.plan);
      m['dpd_31_60_actual'] = _s(d.dpd3160.actual);
      m['dpd_31_60_plan'] = _s(d.dpd3160.plan);
      m['dpd_61_90_actual'] = _s(d.dpd6190.actual);
      m['dpd_61_90_plan'] = _s(d.dpd6190.plan);
      m['fy_non_start_acc'] = _s(d.fyNonStart.actual);
      m['fy_non_start_plan'] = _s(d.fyNonStart.plan);
      m['disb_igl_acc'] = _s(d.igl.acc);
      m['disb_igl_amt'] = _s(d.igl.amt);
      m['disb_fig_acc'] = _s(d.fig.acc);
      m['disb_fig_amt'] = _s(d.fig.amt);
      m['disb_il_acc'] = _s(d.il.acc);
      m['disb_il_amt'] = _s(d.il.amt);
      m['kyc_igl'] = _s(d.kycIgl);
      m['kyc_fig'] = _s(d.kycFig);
      m['kyc_il'] = _s(d.kycIl);
      m['npa_activation'] = _s(d.npaActivation);
      m['npa_closure'] = _s(d.npaClosure);
    }
    for (final k in _fields) {
      _c[k]!.text = m[k] ?? '';
    }
  }

  double _n(String k) {
    final t = _c[k]!.text.trim();
    return t.isEmpty ? 0 : (double.tryParse(t) ?? 0);
  }

  void _setType(String t) {
    setState(() => _type = t);
    _apply(t == 'plan' ? _plan : _ach);
    setState(() => _msg = null);
  }

  void _setDate(String d) {
    setState(() => _date = d);
    _load();
  }

  void _setBranch(String? b) {
    setState(() => _branch = b);
    _load();
  }

  Future<void> _save() async {
    final branch = _activeBranch;
    if (branch == null || branch.isEmpty) {
      setState(() => _msg = (false, 'Select a branch first.'));
      return;
    }
    if (_type == 'achievement') {
      if (!(_plan?.exists ?? false)) {
        setState(() => _msg = (false,
            'Upload the Daily Plan for this date first — the Achievement unlocks once the plan is saved.'));
        return;
      }
      if (_isToday && DateTime.now().hour < 18) {
        setState(() => _msg = (false,
            'Achievement can only be uploaded after 6:00 PM. Please come back this evening.'));
        return;
      }
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final payload = <String, dynamic>{
        'plan_date': _date,
        'submission_type': _type,
        if (_pickerMode) 'branch': branch,
        'ftod': {'actual': _n('ftod_actual'), 'plan': _n('ftod_plan')},
        'dpd': {
          '1_30': {'actual': _n('dpd_1_30_actual'), 'plan': _n('dpd_1_30_plan')},
          '31_60': {
            'actual': _n('dpd_31_60_actual'),
            'plan': _n('dpd_31_60_plan')
          },
          '61_90': {
            'actual': _n('dpd_61_90_actual'),
            'plan': _n('dpd_61_90_plan')
          },
        },
        'fy_non_start': {
          'actual': _n('fy_non_start_acc'),
          'plan': _n('fy_non_start_plan')
        },
        'disb': {
          'igl': {'acc': _n('disb_igl_acc'), 'amt': _n('disb_igl_amt')},
          'fig': {'acc': _n('disb_fig_acc'), 'amt': _n('disb_fig_amt')},
          'il': {'acc': _n('disb_il_acc'), 'amt': _n('disb_il_amt')},
        },
        'kyc': {
          'igl': _n('kyc_igl'),
          'fig': _n('kyc_fig'),
          'il': _n('kyc_il')
        },
        'npa': {
          'activation': _n('npa_activation'),
          'closure': _n('npa_closure')
        },
      };
      await ref.read(misRepositoryProvider).dailyPlanSave(payload);
      if (!mounted) return;
      setState(() => _msg =
          (true, '${_type == 'plan' ? 'Daily Plan' : 'Achievement'} saved.'));
      await _load();
    } catch (e) {
      if (mounted) setState(() => _msg = (false, e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _chainWarn =>
      _type == 'plan' &&
      _date == _todayIso() &&
      (_yPlan?.exists ?? false) &&
      !(_yAch?.exists ?? false);

  // ── Achievement gating ────────────────────────────────────────────────────
  // An Achievement can only be entered after the Daily Plan for the same date
  // has been uploaded, and (for today) only after 6:00 PM.
  bool get _isToday => _date == _todayIso();

  /// Achievement blocked because the plan for this date hasn't been saved yet.
  bool get _achPlanMissing =>
      _type == 'achievement' && !(_plan?.exists ?? false);

  /// Achievement blocked because it's today and before 6 PM.
  bool get _achTooEarly =>
      _type == 'achievement' && _isToday && DateTime.now().hour < 18;

  bool get _achBlocked => _achPlanMissing || _achTooEarly;

  @override
  Widget build(BuildContext context) {
    final planDone = _plan?.exists ?? false;
    final achDone = _ach?.exists ?? false;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Daily Plan')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 14, 16, MediaQuery.of(context).padding.bottom + 32),
        children: [
          // Branch + date + overall status
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _pickerMode
                          ? (_branches.isEmpty
                              ? const Text('No branches available',
                                  style: TextStyle(
                                      color: AppColors.muted, fontSize: 13))
                              : MisDropdown<String>(
                                  value: _branch ?? '',
                                  items: [
                                    for (final b in _branches)
                                      DropdownMenuItem(
                                          value: b.branchName,
                                          child: Text(b.label,
                                              overflow: TextOverflow.ellipsis)),
                                  ],
                                  onChanged: _setBranch,
                                ))
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius:
                                    BorderRadius.circular(AppRadii.pill),
                              ),
                              child: Text(_fixedBranch ?? '—',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary)),
                            ),
                    ),
                    const SizedBox(width: 10),
                    StatusPill(
                      label: planDone && achDone
                          ? 'Day complete'
                          : (planDone || achDone)
                              ? 'In progress'
                              : 'Not started',
                      color: planDone && achDone
                          ? AppColors.success
                          : (planDone || achDone)
                              ? AppColors.warning
                              : AppColors.muted,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_prettyDay(_date),
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted)),
                if (_pickerMode) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final c in [
                        ('Yesterday', _shiftIso(_todayIso(), -1)),
                        ('Today', _todayIso()),
                        ('Tomorrow', _shiftIso(_todayIso(), 1)),
                      ]) ...[
                        _DateChip(
                          label: c.$1,
                          active: _date == c.$2,
                          onTap: () => _setDate(c.$2),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Mode selector
          Row(
            children: [
              Expanded(
                child: _ModeCard(
                  label: 'Daily Plan',
                  hint: 'Morning',
                  icon: Icons.wb_sunny_rounded,
                  active: _type == 'plan',
                  done: planDone,
                  onTap: () => _setType('plan'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ModeCard(
                  label: 'Achievement',
                  hint: 'Evening',
                  icon: Icons.nightlight_round,
                  active: _type == 'achievement',
                  done: achDone,
                  onTap: () => _setType('achievement'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_chainWarn) ...[
            _Banner(
              icon: Icons.warning_amber_rounded,
              color: AppColors.warning,
              text:
                  'Yesterday\'s plan has no achievement recorded for $_activeBranch. Close it before submitting today\'s plan.',
            ),
            const SizedBox(height: 12),
          ],

          if (_achBlocked) ...[
            _Banner(
              icon: _achPlanMissing
                  ? Icons.lock_outline_rounded
                  : Icons.schedule_rounded,
              color: AppColors.warning,
              text: _achPlanMissing
                  ? 'Upload the Daily Plan for this date first. The Achievement unlocks once the plan is saved.'
                  : 'Achievement entry opens after 6:00 PM. Please come back this evening.',
            ),
            const SizedBox(height: 12),
          ],

          if (_loading)
            const AppLoadingBlock(height: 300)
          else ...[
            _group('Collection', AppColors.success, [
              _rowHead('Actual', 'Plan'),
              _row('FTOD', 'ftod_actual', 'ftod_plan'),
              _row('DPD 1-30', 'dpd_1_30_actual', 'dpd_1_30_plan'),
              _row('DPD 31-60', 'dpd_31_60_actual', 'dpd_31_60_plan'),
              _row('DPD 61-90', 'dpd_61_90_actual', 'dpd_61_90_plan'),
              _row('FY Non-Start', 'fy_non_start_acc', 'fy_non_start_plan'),
            ]),
            const SizedBox(height: 12),
            _group('Disbursement', AppColors.primary, [
              _rowHead('Accounts', 'Amount ₹'),
              _row('IGL', 'disb_igl_acc', 'disb_igl_amt'),
              _row('FIG', 'disb_fig_acc', 'disb_fig_amt'),
              _row('IL', 'disb_il_acc', 'disb_il_amt'),
            ]),
            const SizedBox(height: 12),
            _group('KYC', AppColors.warning, [
              Row(
                children: [
                  _cell('IGL', 'kyc_igl'),
                  _cell('FIG', 'kyc_fig'),
                  _cell('IL', 'kyc_il'),
                ],
              ),
            ]),
            const SizedBox(height: 12),
            _group('NPA', AppColors.danger, [
              Row(
                children: [
                  _cell('Activation', 'npa_activation'),
                  _cell('Closure', 'npa_closure'),
                ],
              ),
            ]),
            const SizedBox(height: 16),
            if (_msg != null) ...[
              _Banner(
                icon: _msg!.$1
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
                color: _msg!.$1 ? AppColors.success : AppColors.danger,
                text: _msg!.$2,
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    (_busy || _activeBranch == null || _achBlocked) ? null : _save,
                icon: const Icon(Icons.save_rounded, size: 18),
                label: Text(_busy
                    ? 'Saving…'
                    : 'Save ${_type == 'plan' ? 'Daily Plan' : 'Achievement'}'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _group(String title, Color color, List<Widget> children) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 4, height: 16, color: color),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _rowHead(String a, String b) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 4),
        child: Row(
          children: [
            const Spacer(flex: 4),
            Expanded(
                flex: 3,
                child: Text(a,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted))),
            const SizedBox(width: 8),
            Expanded(
                flex: 3,
                child: Text(b,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted))),
          ],
        ),
      );

  Widget _row(String label, String k1, String k2) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
                flex: 4,
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkSoft))),
            Expanded(flex: 3, child: _input(k1)),
            const SizedBox(width: 8),
            Expanded(flex: 3, child: _input(k2)),
          ],
        ),
      );

  Widget _cell(String label, String k) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted)),
              const SizedBox(height: 4),
              _input(k),
            ],
          ),
        ),
      );

  Widget _input(String k) => TextField(
        controller: _c[k],
        enabled: !_busy,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        textAlign: TextAlign.right,
        decoration: const InputDecoration(
          hintText: '0',
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      );
}

class _DateChip extends StatelessWidget {
  const _DateChip(
      {required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(
              color: active ? AppColors.primary : AppColors.hairline),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : AppColors.inkSoft)),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.label,
    required this.hint,
    required this.icon,
    required this.active,
    required this.done,
    required this.onTap,
  });
  final String label, hint;
  final IconData icon;
  final bool active, done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(
              color: active ? AppColors.primary : AppColors.hairline,
              width: active ? 1.6 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon,
                    size: 18,
                    color: active ? AppColors.primary : AppColors.muted),
                const Spacer(),
                Icon(
                  done ? Icons.check_circle_rounded : Icons.schedule_rounded,
                  size: 14,
                  color: done ? AppColors.success : AppColors.muted,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink)),
            Text(hint,
                style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            const SizedBox(height: 4),
            Text(done ? 'Submitted' : 'Pending',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: done ? AppColors.success : AppColors.warning)),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(
      {required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
