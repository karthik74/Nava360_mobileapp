import 'package:flutter/material.dart';

import '../../features/auth/auth_models.dart';

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

enum MobileModule { home, hrms, payroll, team, more }

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
  });
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
  MobileMenuItem(key: 'hrms.profile', label: 'My Profile', route: '/profile', icon: Icons.person_rounded, module: MobileModule.hrms, order: 2),
  MobileMenuItem(key: 'hrms.attendance', label: 'Attendance', route: '/attendance', icon: Icons.fingerprint_rounded, module: MobileModule.hrms, order: 3),
  MobileMenuItem(key: 'hrms.leaves', label: 'Leaves', route: '/leaves', icon: Icons.event_available_rounded, module: MobileModule.hrms, order: 4),
  MobileMenuItem(key: 'hrms.tasks', label: 'Tasks', route: '/tasks', icon: Icons.task_alt_rounded, module: MobileModule.hrms, order: 5),
  MobileMenuItem(key: 'hrms.chats', label: 'Chats', route: '/chats', icon: Icons.chat_rounded, module: MobileModule.hrms, order: 6),
  MobileMenuItem(key: 'hrms.interviews', label: 'My Interviews', route: '/interviews', icon: Icons.event_note_rounded, module: MobileModule.hrms, order: 7, requiredPermissions: ['INTERVIEW_VIEW']),
  MobileMenuItem(key: 'hrms.requisitions', label: 'Job Requisitions', route: '/requisitions', icon: Icons.work_outline_rounded, module: MobileModule.hrms, order: 8, requiredPermissions: ['REQUISITION_VIEW']),
  MobileMenuItem(key: 'hrms.travelClaims', label: 'Travel Claims', route: '/travel/claims', icon: Icons.flight_takeoff_rounded, module: MobileModule.hrms, order: 9),
  MobileMenuItem(key: 'hrms.travelPlans', label: 'Travel Plans', route: '/travel/plans', icon: Icons.luggage_rounded, module: MobileModule.hrms, order: 10),
  MobileMenuItem(key: 'hrms.announcements', label: 'Announcements', route: '/announcements', icon: Icons.campaign_rounded, module: MobileModule.hrms, order: 11),
  MobileMenuItem(key: 'hrms.policies', label: 'Policies', route: '/policies', icon: Icons.description_rounded, module: MobileModule.hrms, order: 12),
  MobileMenuItem(key: 'hrms.meetings', label: 'My Meetings', route: '/my-meetings', icon: Icons.event_rounded, module: MobileModule.hrms, order: 13),
  MobileMenuItem(key: 'hrms.trainings', label: 'My Trainings', route: '/my-trainings', icon: Icons.school_rounded, module: MobileModule.hrms, order: 14),
  MobileMenuItem(key: 'hrms.assets', label: 'My Assets', route: '/assets', icon: Icons.devices_other_rounded, module: MobileModule.hrms, order: 15),
  MobileMenuItem(key: 'hrms.resignation', label: 'My Resignation', route: '/my-resignation', icon: Icons.logout_rounded, module: MobileModule.hrms, order: 16),
  MobileMenuItem(key: 'hrms.performance', label: 'My Performance', route: '/my-performance', icon: Icons.insights_rounded, module: MobileModule.hrms, order: 17, requiredPermissions: ['VIEW_SELF_PERFORMANCE']),
  // Whistleblower is intentionally NOT in the menu — reached via the dashboard's
  // "Report a concern" button (keeps the reporting entry low-profile).

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
  if (!m.employeeAllowed && !isManager) return false; // manager-only gate
  if (!m.managerAllowed && isManager) return false;
  return _passesPermissions(m, user); // (2) ANY-of permission
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
  MobileModuleInfo(module: MobileModule.team, label: 'My Team', route: '/team', icon: Icons.supervisor_account_rounded, managerOnly: true),
  MobileModuleInfo(module: MobileModule.more, label: 'More', route: '/more', icon: Icons.more_horiz_rounded),
];

/// Modules visible to the user (My Team only for managers).
List<MobileModuleInfo> modulesFor(AuthUser? user) {
  final isManager = isManagerUser(user);
  return kMobileModules.where((m) => !m.managerOnly || isManager).toList();
}
