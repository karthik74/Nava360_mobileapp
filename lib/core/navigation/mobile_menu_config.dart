import 'package:flutter/material.dart';

import '../../features/auth/auth_models.dart';
import '../branding.dart';

/// ───────────────────────────────────────────────────────────────────────────
///  CENTRALIZED MOBILE NAVIGATION — single source of truth for the bottom nav
///  and every module screen (HRMS / Payroll / My Team / More).
///
///  The mobile app is **employee + manager self-service only**. Admin, IT/Admin,
///  master-data, role/permission/branch/department/designation setup, payroll
///  processing and monitoring dashboards are WEB-ONLY and never appear here
///  (`webOnly: true` / `mobileAllowed: false`).
///
///  `home_shell.dart` and the module screens READ from this file — do not
///  hardcode menu tiles in the UI. GoRouter route definitions stay in app.dart.
/// ───────────────────────────────────────────────────────────────────────────

enum MobileModule { home, hrms, payroll, team, mis, more }

class MobileMenuItem {
  final String key;
  final String label;
  final String route;
  final IconData icon;
  final MobileModule module;
  final int order;

  /// Visible if the user holds ANY of these (empty ⇒ no permission needed).
  final List<String> requiredPermissions;

  /// Visibility by audience.
  final bool employeeAllowed;
  final bool managerAllowed;

  /// Platform scoping. `webOnly` or `mobileAllowed == false` ⇒ never on mobile.
  final bool webOnly;
  final bool mobileAllowed;

  /// Root entries rendered in the bottom navigation bar.
  final bool showInBottomNav;

  /// Runtime feature flag (SettingKey name, e.g. `FEATURE_CHAT`) — hidden when
  /// the deployment turns it off via /api/public/branding.
  final String? featureFlag;

  /// Backend module code (web menuConfig top-level key, e.g. `helpdesk`)
  /// gating this item through ENABLED_MODULES. Defaults to the code of the
  /// item's own [module]; set explicitly for items that belong to a different
  /// web module (helpdesk/audit entries living under the HRMS grid).
  final String? moduleCode;

  const MobileMenuItem({
    required this.key,
    required this.label,
    required this.route,
    required this.icon,
    required this.module,
    this.order = 0,
    this.requiredPermissions = const [],
    this.employeeAllowed = true,
    this.managerAllowed = true,
    this.webOnly = false,
    this.mobileAllowed = true,
    this.showInBottomNav = false,
    this.featureFlag,
    this.moduleCode,
  });
}

/// ENABLED_MODULES code for a mobile module (matches the web menuConfig
/// top-level keys); null = never toggled off.
String? _moduleCodeOf(MobileModule m) {
  switch (m) {
    case MobileModule.hrms:
      return 'hrms';
    case MobileModule.payroll:
      return 'payroll';
    case MobileModule.mis:
      return 'mis';
    default:
      return null;
  }
}

const List<MobileMenuItem> kMobileMenu = [
  // ── Bottom-nav roots ──
  // Bottom nav: Home · Tasks · My Team* · More. (HRMS & Payroll are NOT bottom-nav
  // tabs — they remain accessible from the drawer's HRMS / PAYROLL sections.)
  MobileMenuItem(key: 'home', label: 'Home', route: '/home', icon: Icons.home_rounded, module: MobileModule.home, order: 0, showInBottomNav: true),
  MobileMenuItem(key: 'nav.tasks', label: 'Tasks', route: '/tasks', icon: Icons.task_alt_rounded, module: MobileModule.hrms, order: 1, showInBottomNav: true),
  MobileMenuItem(key: 'team', label: 'My Team', route: '/team', icon: Icons.supervisor_account_rounded, module: MobileModule.team, order: 3, employeeAllowed: false, showInBottomNav: true),
  // Performance replaces the old "More" bottom-nav tab. Visible to everyone: it shows
  // the user's own scorecard plus (for managers/HR) their direct+indirect downline.
  // The More MODULE screen (/more) and its items remain reachable from the drawer.
  MobileMenuItem(key: 'nav.performance', label: 'Performance', route: '/performance', icon: Icons.insights_rounded, module: MobileModule.hrms, order: 4, showInBottomNav: true),

  // ── HRMS module cards ──
  // Dashboard (= Home) is surfaced as the drawer's top tile / Home tab, not an HRMS item.
  // AI Assistant intentionally has no menu entry — it's the sparkle button
  // at the top-right of the Home screen app bar (home_shell._AssistantButton),
  // still gated by FEATURE_AI_ASSISTANT.
  MobileMenuItem(key: 'hrms.profile', label: 'My Profile', route: '/profile', icon: Icons.person_rounded, module: MobileModule.hrms, order: 2),
  // My Business Card intentionally has no menu entry — it lives inside
  // My Profile (Documents section), next to My documents.
  MobileMenuItem(key: 'hrms.attendance', label: 'Attendance', route: '/attendance', icon: Icons.fingerprint_rounded, module: MobileModule.hrms, order: 3),
  MobileMenuItem(key: 'hrms.leaves', label: 'Leaves', route: '/leaves', icon: Icons.event_available_rounded, module: MobileModule.hrms, order: 4),
  MobileMenuItem(key: 'hrms.tasks', label: 'Tasks', route: '/tasks', icon: Icons.task_alt_rounded, module: MobileModule.hrms, order: 5),
  // Chats is a bottom-nav root (order 2) — NOT a drawer/HRMS-grid item.
  // showInBottomNav also excludes it from menuFor()/allMenuItems(), so it no
  // longer appears in the left navigation menu.
  MobileMenuItem(key: 'hrms.chats', label: 'Chats', route: '/chats', icon: Icons.chat_rounded, module: MobileModule.hrms, order: 2, showInBottomNav: true, featureFlag: 'FEATURE_CHAT'),
  MobileMenuItem(key: 'hrms.interviews', label: 'My Interviews', route: '/interviews', icon: Icons.event_note_rounded, module: MobileModule.hrms, order: 7, requiredPermissions: ['INTERVIEW_VIEW']),
  MobileMenuItem(key: 'hrms.requisitions', label: 'Job Requisitions', route: '/requisitions', icon: Icons.work_outline_rounded, module: MobileModule.hrms, order: 8, requiredPermissions: ['REQUISITION_VIEW']),
  MobileMenuItem(key: 'hrms.helpdesk', label: 'Helpdesk', route: '/helpdesk', icon: Icons.support_agent_rounded, module: MobileModule.hrms, order: 8, requiredPermissions: ['HELPDESK_CREATE_TICKET'], moduleCode: 'helpdesk'),
  // Knowledge Base lives under More (moved from HRMS 2026-07-04).
  // Helpdesk Dashboard intentionally removed from the mobile drawer (2026-07-04)
  // — it stays a web-only view; the /helpdesk/dashboard route still exists for
  // deep links if ever needed.
  // Travel entries are role-gated: hidden unless the user's roles grant a
  // travel-claim / travel-plan permission (any of create/view).
  MobileMenuItem(key: 'hrms.travelClaims', label: 'Travel Claims', route: '/travel/claims', icon: Icons.flight_takeoff_rounded, module: MobileModule.hrms, order: 9, requiredPermissions: ['TRAVEL_CLAIM_CREATE', 'TRAVEL_CLAIM_VIEW']),
  MobileMenuItem(key: 'hrms.travelPlans', label: 'Travel Plans', route: '/travel/plans', icon: Icons.luggage_rounded, module: MobileModule.hrms, order: 10, requiredPermissions: ['TRAVEL_PLAN_CREATE', 'TRAVEL_PLAN_VIEW']),
  MobileMenuItem(key: 'hrms.announcements', label: 'Announcements', route: '/announcements', icon: Icons.campaign_rounded, module: MobileModule.hrms, order: 11),
  MobileMenuItem(key: 'hrms.policies', label: 'Policies', route: '/policies', icon: Icons.description_rounded, module: MobileModule.hrms, order: 12),
  MobileMenuItem(key: 'hrms.meetings', label: 'My Meetings', route: '/my-meetings', icon: Icons.event_rounded, module: MobileModule.hrms, order: 13),
  MobileMenuItem(key: 'hrms.trainings', label: 'My Trainings', route: '/my-trainings', icon: Icons.school_rounded, module: MobileModule.hrms, order: 14),
  MobileMenuItem(key: 'hrms.assets', label: 'My Assets', route: '/assets', icon: Icons.devices_other_rounded, module: MobileModule.hrms, order: 15),
  MobileMenuItem(key: 'hrms.resignation', label: 'My Resignation', route: '/my-resignation', icon: Icons.logout_rounded, module: MobileModule.hrms, order: 16),
  MobileMenuItem(key: 'hrms.performance', label: 'My Performance', route: '/my-performance', icon: Icons.insights_rounded, module: MobileModule.hrms, order: 17, requiredPermissions: ['VIEW_SELF_PERFORMANCE']),
  MobileMenuItem(key: 'hrms.audit', label: 'Internal Audit', route: '/audit', icon: Icons.fact_check_rounded, module: MobileModule.hrms, order: 18, requiredPermissions: ['AUDIT_PERFORM', 'AUDIT_VIEW_BRANCH', 'AUDIT_VIEW_HIERARCHY', 'AUDIT_VIEW_ALL', 'AUDIT_BM_COMPLIANCE', 'AUDIT_VERIFY'], moduleCode: 'audit'),
  // Whistleblower is intentionally NOT in the menu — reached via the dashboard's
  // "Report a concern" button (keeps the reporting entry low-profile).

  // ── MIS · Grow With Me module (its OWN module, not under HRMS) ──
  // A separate backend + auto-login (derived from the nava360 identity). Ungated
  // for now — mirrors the web sidebar, where every logged-in user gets a MIS
  // session; add requiredPermissions here to limit MIS to specific roles.
  // Order mirrors the website's MIS menu.
  MobileMenuItem(key: 'mis.dashboard', label: 'Dashboard', route: '/mis', icon: Icons.dashboard_rounded, module: MobileModule.mis, order: 1),
  MobileMenuItem(key: 'mis.portfolio', label: 'Portfolio', route: '/mis/portfolio', icon: Icons.pie_chart_rounded, module: MobileModule.mis, order: 2),
  MobileMenuItem(key: 'mis.collection', label: 'Collection', route: '/mis/collection', icon: Icons.payments_rounded, module: MobileModule.mis, order: 3),
  MobileMenuItem(key: 'mis.disbursement', label: 'Disbursement', route: '/mis/disbursement', icon: Icons.account_balance_rounded, module: MobileModule.mis, order: 4),
  MobileMenuItem(key: 'mis.hourly', label: 'Hourly', route: '/mis/hourly', icon: Icons.schedule_rounded, module: MobileModule.mis, order: 5),
  MobileMenuItem(key: 'mis.comparison', label: 'Comparison', route: '/mis/comparison', icon: Icons.compare_arrows_rounded, module: MobileModule.mis, order: 6),
  MobileMenuItem(key: 'mis.analytical', label: 'Analytical', route: '/mis/analytical', icon: Icons.query_stats_rounded, module: MobileModule.mis, order: 7),
  MobileMenuItem(key: 'mis.dailyPlan', label: 'Daily Plan', route: '/mis/daily-plan', icon: Icons.edit_note_rounded, module: MobileModule.mis, order: 8),
  MobileMenuItem(key: 'mis.feedback', label: 'Feedback', route: '/mis/feedback', icon: Icons.forum_rounded, module: MobileModule.mis, order: 9),
  MobileMenuItem(key: 'mis.employees', label: 'Directory', route: '/mis/employees', icon: Icons.contacts_rounded, module: MobileModule.mis, order: 10),
  MobileMenuItem(key: 'mis.locations', label: 'Locations', route: '/mis/locations', icon: Icons.map_rounded, module: MobileModule.mis, order: 11),

  // ── Payroll module cards (self-service only) ──
  MobileMenuItem(key: 'pay.payslips', label: 'My Payslips', route: '/my-payslips', icon: Icons.receipt_long_rounded, module: MobileModule.payroll, order: 1),
  MobileMenuItem(key: 'pay.salary', label: 'Salary Details', route: '/my-payslips', icon: Icons.account_balance_wallet_rounded, module: MobileModule.payroll, order: 2),
  MobileMenuItem(key: 'pay.taxdocs', label: 'Tax Documents', route: '/my-payslips', icon: Icons.folder_shared_rounded, module: MobileModule.payroll, order: 3, requiredPermissions: ['ITR_DOCUMENT_VIEW_MY']),
  MobileMenuItem(key: 'pay.taxdecl', label: 'Tax Declaration', route: '/my-payslips', icon: Icons.edit_document, module: MobileModule.payroll, order: 4),
  MobileMenuItem(key: 'pay.pfesi', label: 'PF / ESI Info', route: '/my-payslips', icon: Icons.savings_rounded, module: MobileModule.payroll, order: 5),

  // ── My Team module cards (managers only) ──
  MobileMenuItem(key: 'team.dashboard', label: 'Team Dashboard', route: '/team', icon: Icons.dashboard_customize_rounded, module: MobileModule.team, order: 1, employeeAllowed: false),
  MobileMenuItem(key: 'team.members', label: 'Team Members', route: '/team', icon: Icons.badge_rounded, module: MobileModule.team, order: 2, employeeAllowed: false, requiredPermissions: ['EMPLOYEE_VIEW']),
  MobileMenuItem(key: 'team.attendance', label: 'Team Attendance', route: '/team', icon: Icons.how_to_reg_rounded, module: MobileModule.team, order: 3, employeeAllowed: false),
  MobileMenuItem(key: 'team.leaves', label: 'Team Leaves', route: '/team', icon: Icons.event_busy_rounded, module: MobileModule.team, order: 4, employeeAllowed: false),
  MobileMenuItem(key: 'team.tasks', label: 'Team Tasks', route: '/team', icon: Icons.assignment_ind_rounded, module: MobileModule.team, order: 5, employeeAllowed: false, requiredPermissions: ['TASK_VIEW']),
  MobileMenuItem(key: 'team.approvals', label: 'Team Approvals', route: '/team', icon: Icons.fact_check_rounded, module: MobileModule.team, order: 6, employeeAllowed: false),
  MobileMenuItem(key: 'team.travelApprovals', label: 'Travel Approvals', route: '/travel/approvals', icon: Icons.connecting_airports_rounded, module: MobileModule.team, order: 7, employeeAllowed: false, requiredPermissions: ['TRAVEL_CLAIM_APPROVE']),
  MobileMenuItem(key: 'team.hierarchy', label: 'Hierarchy', route: '/team', icon: Icons.account_tree_rounded, module: MobileModule.team, order: 8, employeeAllowed: false),

  // ── More ──
  MobileMenuItem(key: 'more.notifications', label: 'Notifications', route: '/notifications', icon: Icons.notifications_rounded, module: MobileModule.more, order: 1),
  MobileMenuItem(key: 'more.password', label: 'Change Password', route: '/change-password', icon: Icons.lock_rounded, module: MobileModule.more, order: 2),
  MobileMenuItem(key: 'more.support', label: 'Help / Support', route: '/help-support', icon: Icons.help_rounded, module: MobileModule.more, order: 3),
  MobileMenuItem(key: 'more.helpdeskKb', label: 'Knowledge Base', route: '/helpdesk/kb', icon: Icons.menu_book_rounded, module: MobileModule.more, order: 4, moduleCode: 'helpdesk'),
];

/// True when the signed-in user may see manager-only entries. Heuristic (until
/// the backend exposes employeeType/reporteeCount on mobile): Admin, or anyone
/// holding EMPLOYEE_VIEW (HR / MANAGER / custom managerial roles).
bool isManagerUser(AuthUser? user) =>
    (user?.hasRole(const {'ADMIN'}) ?? false) ||
    (user?.hasPermission('EMPLOYEE_VIEW') ?? false);

bool _passesPermissions(MobileMenuItem m, AuthUser? user) =>
    m.requiredPermissions.isEmpty ||
    m.requiredPermissions.any((p) => user?.hasPermission(p) ?? false);

bool _visible(MobileMenuItem m, AuthUser? user, bool isManager) {
  if (m.webOnly || !m.mobileAllowed) return false; // (1) drop web-only
  // (2) runtime deployment config (/api/public/branding): module toggles +
  // feature flags — same semantics as the web's moduleEnabled/featureEnabled.
  final branding = Branding.current;
  final code = m.moduleCode ?? _moduleCodeOf(m.module);
  if (code != null && !branding.moduleEnabled(code)) return false;
  if (m.featureFlag != null && !branding.featureEnabled(m.featureFlag!)) {
    return false;
  }
  if (!m.employeeAllowed && !isManager) return false; // manager-only gate
  if (!m.managerAllowed && isManager) return false;
  return _passesPermissions(m, user); // (3) ANY-of permission
}

/// Cards for a module, filtered for the user and sorted by order. (5)
List<MobileMenuItem> menuFor(MobileModule module, AuthUser? user) {
  final isManager = isManagerUser(user);
  final list = kMobileMenu
      .where((m) => m.module == module && !m.showInBottomNav && _visible(m, user, isManager))
      .toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  return list;
}

/// Bottom-nav root tabs for the user (My Team hidden for non-managers).
List<MobileMenuItem> bottomNavTabs(AuthUser? user) {
  final isManager = isManagerUser(user);
  return kMobileMenu
      .where((m) => m.showInBottomNav && _visible(m, user, isManager))
      .toList()
    ..sort((a, b) => a.order.compareTo(b.order));
}

/// Every visible menu item across modules, flattened (used by the drawer's
/// quick-search). Excludes bottom-nav roots.
List<MobileMenuItem> allMenuItems(AuthUser? user) {
  final isManager = isManagerUser(user);
  return kMobileMenu
      .where((m) => !m.showInBottomNav && _visible(m, user, isManager))
      .toList()
    ..sort((a, b) => a.order.compareTo(b.order));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Module descriptors — the top-level "module list" shown in the drawer. Each
//  entry opens that module's screen (a grid of its menus). Separate from the
//  menu items so module roots never leak into the per-module grids.
// ─────────────────────────────────────────────────────────────────────────────

class MobileModuleInfo {
  final MobileModule module;
  final String label;
  final String route; // module screen route
  final IconData icon;
  final bool managerOnly;
  const MobileModuleInfo({
    required this.module,
    required this.label,
    required this.route,
    required this.icon,
    this.managerOnly = false,
  });
}

const List<MobileModuleInfo> kMobileModules = [
  MobileModuleInfo(module: MobileModule.home, label: 'Home', route: '/home', icon: Icons.home_rounded),
  MobileModuleInfo(module: MobileModule.hrms, label: 'HRMS', route: '/hrms', icon: Icons.groups_rounded),
  MobileModuleInfo(module: MobileModule.payroll, label: 'Payroll', route: '/payroll', icon: Icons.payments_rounded),
  MobileModuleInfo(module: MobileModule.mis, label: 'MIS', route: '/mis', icon: Icons.query_stats_rounded),
  MobileModuleInfo(module: MobileModule.team, label: 'My Team', route: '/team', icon: Icons.supervisor_account_rounded, managerOnly: true),
  MobileModuleInfo(module: MobileModule.more, label: 'More', route: '/more', icon: Icons.more_horiz_rounded),
];

/// Modules visible to the user (My Team only for managers; modules the
/// deployment disabled via ENABLED_MODULES are dropped for everyone).
List<MobileModuleInfo> modulesFor(AuthUser? user) {
  final isManager = isManagerUser(user);
  return kMobileModules.where((m) {
    if (m.managerOnly && !isManager) return false;
    final code = _moduleCodeOf(m.module);
    return code == null || Branding.current.moduleEnabled(code);
  }).toList();
}
