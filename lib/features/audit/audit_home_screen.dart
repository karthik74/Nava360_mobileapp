// ─────────────────────────────────────────────────────────────────────────────
//  Branch Internal Audit — entry screen (route: /audit).
//
//  Tabs mirror the web menu (repo/src/nav/menuConfig.ts audit.* entries) with
//  the same permission gates:
//    Dashboard   any audit permission          (audit.dashboard)
//    Audit Plans view / assign / create        (audit.plans)
//    My Audits   AUDIT_PERFORM                 (audit.myAudits)
//    Findings    view / BM compliance / verify (audit.findings)
//  Users with dashboard-level access land on the Dashboard; pure auditors
//  (AUDIT_PERFORM only) land on My Audits. The Template Builder is web-only.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../auth/auth_controller.dart';
import 'audit_dashboard_screen.dart';
import 'audit_plan_form_screen.dart';
import 'findings_list_screen.dart';
import 'my_audits_screen.dart';

const _kDashboardPerms = [
  'AUDIT_ADMIN', 'AUDIT_VIEW_ALL', 'AUDIT_VIEW_HIERARCHY', 'AUDIT_VIEW_BRANCH',
  'AUDIT_PERFORM', 'AUDIT_ASSIGN', 'AUDIT_PLAN_CREATE', 'AUDIT_BM_COMPLIANCE',
  'AUDIT_VERIFY',
];
const _kPlansPerms = [
  'AUDIT_ADMIN', 'AUDIT_VIEW_ALL', 'AUDIT_VIEW_HIERARCHY', 'AUDIT_VIEW_BRANCH',
  'AUDIT_ASSIGN', 'AUDIT_PLAN_CREATE',
];
const _kMyAuditsPerms = ['AUDIT_PERFORM'];
const _kFindingsPerms = [
  'AUDIT_ADMIN', 'AUDIT_VIEW_ALL', 'AUDIT_VIEW_HIERARCHY', 'AUDIT_VIEW_BRANCH',
  'AUDIT_BM_COMPLIANCE', 'AUDIT_VERIFY',
];
// Dashboard perms other than the bare auditor one — decides the landing tab.
const _kLandOnDashboardPerms = [
  'AUDIT_ADMIN', 'AUDIT_VIEW_ALL', 'AUDIT_VIEW_HIERARCHY', 'AUDIT_VIEW_BRANCH',
  'AUDIT_ASSIGN', 'AUDIT_PLAN_CREATE', 'AUDIT_BM_COMPLIANCE', 'AUDIT_VERIFY',
];

enum _Tab { dashboard, plans, myAudits, findings }

class AuditHomeScreen extends ConsumerStatefulWidget {
  const AuditHomeScreen({super.key});

  @override
  ConsumerState<AuditHomeScreen> createState() => _AuditHomeScreenState();
}

class _AuditHomeScreenState extends ConsumerState<AuditHomeScreen>
    with TickerProviderStateMixin {
  TabController? _ctrl;
  List<_Tab> _tabs = const [];

  static bool _any(Set<String>? held, List<String> want) =>
      held != null && want.any(held.contains);

  List<_Tab> _computeTabs(Set<String> held) {
    final tabs = <_Tab>[
      if (_any(held, _kDashboardPerms)) _Tab.dashboard,
      if (_any(held, _kPlansPerms)) _Tab.plans,
      if (_any(held, _kMyAuditsPerms)) _Tab.myAudits,
      if (_any(held, _kFindingsPerms)) _Tab.findings,
    ];
    // Never render an empty shell; the backend still enforces access per call.
    return tabs.isEmpty ? const [_Tab.myAudits] : tabs;
  }

  void _sync(Set<String> held) {
    final next = _computeTabs(held);
    if (next.length == _tabs.length &&
        Iterable<int>.generate(next.length).every((i) => next[i] == _tabs[i])) {
      return;
    }
    _ctrl?.dispose();
    _tabs = next;
    final land = _any(held, _kLandOnDashboardPerms) && next.contains(_Tab.dashboard)
        ? next.indexOf(_Tab.dashboard)
        : (next.contains(_Tab.myAudits) ? next.indexOf(_Tab.myAudits) : 0);
    _ctrl = TabController(length: next.length, vsync: this, initialIndex: land)
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  static String _label(_Tab t) => switch (t) {
        _Tab.dashboard => 'Dashboard',
        _Tab.plans => 'Audit Plans',
        _Tab.myAudits => 'My Audits',
        _Tab.findings => 'Findings & CAPA',
      };

  Widget _body(_Tab t) => switch (t) {
        _Tab.dashboard => const AuditDashboardBody(),
        _Tab.plans => const MyAuditsScreen(embedded: true, mine: false),
        _Tab.myAudits => const MyAuditsScreen(embedded: true, mine: true),
        _Tab.findings => const FindingsListScreen(embedded: true),
      };

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    _sync(user?.permissions ?? const <String>{});
    final ctrl = _ctrl!;
    final canCreate = (user?.hasPermission('AUDIT_PLAN_CREATE') ?? false) ||
        (user?.hasPermission('AUDIT_ADMIN') ?? false);
    final onPlans = _tabs[ctrl.index] == _Tab.plans;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Internal Audit'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        bottom: _tabs.length > 1
            ? TabBar(
                controller: ctrl,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.muted,
                indicatorColor: AppColors.primary,
                tabs: [for (final t in _tabs) Tab(text: _label(t))],
              )
            : null,
      ),
      floatingActionButton: (onPlans && canCreate)
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AuditPlanFormScreen(),
              )),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New plan'),
            )
          : null,
      body: SafeArea(
        child: TabBarView(
          controller: ctrl,
          physics: const NeverScrollableScrollPhysics(),
          children: [for (final t in _tabs) _body(t)],
        ),
      ),
    );
  }
}
