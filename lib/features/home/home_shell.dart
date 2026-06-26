import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../announcements/announcements_repository.dart';
import '../policies/policies_repository.dart';
import '../auth/auth_controller.dart';
import '../chat/chat_controller.dart';
import '../leaves/leave_repository.dart';
import '../tasks/task_repository.dart';

// ─────────────────────────────────────────────────────────────────────
// Drawer badge counters — populated when the drawer is on screen.
// autoDispose so they don't keep firing on every screen.
// ─────────────────────────────────────────────────────────────────────

final _drawerPendingLeavesProvider = FutureProvider.autoDispose<int>((ref) async {
  final user = ref.watch(authUserProvider);
  if (user?.employeeId == null) return 0;
  final leaves = await ref
      .watch(leaveRepositoryProvider)
      .listForEmployee(user!.employeeId!);
  return leaves.where((l) => l.status == 'PENDING').length;
});

final _drawerActiveTasksProvider = FutureProvider.autoDispose<int>((ref) async {
  final user = ref.watch(authUserProvider);
  if (user?.employeeId == null) return 0;
  final tasks = await ref
      .watch(taskRepositoryProvider)
      .listForEmployee(user!.employeeId!);
  return tasks
      .where((t) => t.status == 'PENDING' || t.status == 'IN_PROGRESS')
      .length;
});

/// Employee profile cache. NOT autoDispose — fetched once per session and
/// reused, so opening the drawer (or other consumers) doesn't re-hit
/// /api/employees/{id} every time. Invalidate it after a profile edit
/// (e.g. photo upload) to refresh.
final employeeProfileProvider =
    FutureProvider.family<Map<String, dynamic>?, int>((ref, employeeId) async {
  final api = ref.watch(apiClientProvider);
  try {
    return await api.get<Map<String, dynamic>>(
      '/api/employees/$employeeId',
      parse: (d) => d as Map<String, dynamic>,
    );
  } catch (_) {
    return null;
  }
});

final _drawerUnreadAnnouncementsProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final user = ref.watch(authUserProvider);
  if (user?.employeeId == null) return 0;
  try {
    return await ref.watch(announcementsRepositoryProvider).getUnreadCount();
  } catch (_) {
    return 0;
  }
});

final _drawerUnreadPoliciesProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final user = ref.watch(authUserProvider);
  if (user?.employeeId == null) return 0;
  try {
    final list = await ref.watch(policiesRepositoryProvider).myPolicies();
    return list.where((p) => !p.read).length;
  } catch (_) {
    return 0;
  }
});

final _drawerPendingApprovalsProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final user = ref.watch(authUserProvider);
  final isManager = user?.hasRole(const {'ADMIN', 'HR'}) ?? false;
  if (!isManager) return 0;
  final leaves = await ref.watch(leaveRepositoryProvider).listForTeam();
  return leaves.where((l) => l.status == 'PENDING').length;
});

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.child});
  final Widget child;

  // Bottom-nav tabs — Attendance removed
  static const _bottomTabs = [
    _Tab(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      path: '/home',
    ),
    _Tab(
      label: 'Tasks',
      icon: Icons.task_alt_outlined,
      selectedIcon: Icons.task_alt_rounded,
      path: '/tasks',
    ),
    _Tab(
      label: 'Team',
      icon: Icons.groups_2_outlined,
      selectedIcon: Icons.groups_2_rounded,
      path: '/team',
    ),
  ];

  int _indexFromLocation(String loc, List<_Tab> tabs) {
    for (var i = 0; i < tabs.length; i++) {
      if (loc.startsWith(tabs[i].path)) return i;
    }
    return 0;
  }

  String _titleFor(String loc) {
    if (loc.startsWith('/home')) return 'Dashboard';
    if (loc.startsWith('/attendance')) return 'Attendance';
    if (loc.startsWith('/leaves')) return 'Leaves';
    if (loc.startsWith('/tasks')) return 'Tasks';
    if (loc.startsWith('/team')) return 'Team';
    return 'Nava360';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = GoRouterState.of(context).matchedLocation;
    final user = ref.watch(authUserProvider);
    // Anyone who can have a team sees the Team tab. Gated on EMPLOYEE_VIEW
    // (held by HR, MANAGER and any custom managerial role) rather than hard-coded
    // role names, so it survives the dynamic RBAC setup. Admin always sees it.
    // The Team screen shows "No team members…" gracefully if they have none.
    final isManager = (user?.hasRole(const {'ADMIN'}) ?? false) ||
        (user?.hasPermission('EMPLOYEE_VIEW') ?? false);
    final visibleTabs = isManager ? _bottomTabs : _bottomTabs.take(2).toList();
    final index = _indexFromLocation(loc, visibleTabs);

    return Scaffold(
      key: const ValueKey('home_shell_scaffold'),
      backgroundColor: Colors.transparent,
      extendBody: true,
      extendBodyBehindAppBar: true,
      drawer: _AppDrawer(currentPath: loc, isManager: isManager),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(
          MediaQuery.of(context).padding.top + AppChrome.appBarHeight,
        ),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: GlassBlur.chrome,
              sigmaY: GlassBlur.chrome,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  bottom: BorderSide(color: AppColors.hairline),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
                  child: Row(
                    children: [
                      Builder(
                        builder: (ctx) => _HamburgerButton(
                          onTap: () => Scaffold.of(ctx).openDrawer(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => context.push('/profile'),
                        child: UserAvatar(
                          name: user?.username ?? '',
                          size: 36,
                          radius: 11,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _titleFor(loc),
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                                letterSpacing: -0.1,
                              ),
                            ),
                            Text(
                              user?.username ?? '',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.muted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: GlassBackdrop(
        child: SafeArea(
          top: false,
          bottom: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (c, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.02),
                  end: Offset.zero,
                ).animate(anim),
                child: c,
              ),
            ),
            child: KeyedSubtree(key: ValueKey(loc), child: child),
          ),
        ),
      ),
      // Hidden on the attendance screen so it never overlaps the day-action
      // sheets' submit buttons.
      bottomNavigationBar: loc.startsWith('/attendance') ? null : ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: GlassBlur.chrome,
            sigmaY: GlassBlur.chrome,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(
                top: BorderSide(color: AppColors.hairline),
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x0D0F172A),
                  blurRadius: 12,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  children: [
                    for (var i = 0; i < visibleTabs.length; i++)
                      Expanded(
                        child: _NavItem(
                          tab: visibleTabs[i],
                          selected: i == index,
                          onTap: () => context.go(visibleTabs[i].path),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HamburgerButton extends StatelessWidget {
  const _HamburgerButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 38,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: Colors.white.withOpacity(0.55),
            child: InkWell(
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: Colors.white.withOpacity(0.55)),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.menu_rounded,
                  size: 18,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Left Navigation Drawer
//
// Layout (top → bottom):
//   • Brand row     (gradient mark + workspace + close)
//   • Search field  (filters nav items locally)
//   • Nav           (Overview / Workspace sections with badges)
//   • + New leave   (dashed-bordered action)
//   • User card     (avatar + status dot + email + sign-out)
// ─────────────────────────────────────────────────────────────────────

/// Single nav-item descriptor used to drive both the visible link and the
/// search filter without restating fields each time.
class _NavItemData {
  const _NavItemData({
    required this.label,
    required this.icon,
    required this.path,
    this.accent,
    this.badge,
    this.badgeAsString = false,
    this.isPush = false,
  });

  final String label;
  final IconData icon;
  final String path;
  final Color? accent;

  /// Numeric badge (rendered with ring tint). Pass null/0 to hide.
  final int? badge;

  /// When true, treat `badge` as 0/1 boolean rendered as "New" (emerald tint).
  final bool badgeAsString;
  final bool isPush;
}

class _AppDrawer extends ConsumerStatefulWidget {
  const _AppDrawer({required this.currentPath, required this.isManager});
  final String currentPath;
  final bool isManager;

  @override
  ConsumerState<_AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<_AppDrawer> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    final mq = MediaQuery.of(context);

    final pendingLeaves =
        ref.watch(_drawerPendingLeavesProvider).asData?.value ?? 0;
    final activeTasks =
        ref.watch(_drawerActiveTasksProvider).asData?.value ?? 0;
    final pendingApprovals =
        ref.watch(_drawerPendingApprovalsProvider).asData?.value ?? 0;
    final unreadAnnouncements =
        ref.watch(_drawerUnreadAnnouncementsProvider).asData?.value ?? 0;
    final unreadPolicies =
        ref.watch(_drawerUnreadPoliciesProvider).asData?.value ?? 0;

    final overviewItems = <_NavItemData>[
      const _NavItemData(
        label: 'Dashboard',
        icon: Icons.home_rounded,
        path: '/home',
      ),
      const _NavItemData(
        label: 'Attendance',
        icon: Icons.fingerprint_rounded,
        path: '/attendance',
        accent: AppColors.accent,
      ),
      _NavItemData(
        label: 'Leaves',
        icon: Icons.event_available_rounded,
        path: '/leaves',
        accent: AppColors.success,
        badge: pendingLeaves > 0 ? pendingLeaves : null,
      ),
      _NavItemData(
        label: 'Tasks',
        icon: Icons.task_alt_rounded,
        path: '/tasks',
        accent: AppColors.warning,
        badge: activeTasks > 0 ? activeTasks : null,
      ),
    ];

    final unreadChats = ref.watch(totalUnreadProvider);

    final workspaceItems = <_NavItemData>[
      _NavItemData(
        label: 'Chats',
        icon: Icons.chat_rounded,
        path: '/chats',
        accent: AppColors.accent,
        badge: unreadChats > 0 ? unreadChats : null,
        isPush: true,
      ),
      if (widget.isManager)
        _NavItemData(
          label: 'Team',
          icon: Icons.groups_2_rounded,
          path: '/team',
          accent: AppColors.pink,
          badge: pendingApprovals > 0 ? pendingApprovals : null,
        ),
      // Recruitment — shown per the user's permissions (INTERVIEW_VIEW /
      // REQUISITION_CREATE). HR, DHR, RHR, RM and Admin get these.
      if (user?.hasPermission('INTERVIEW_VIEW') ?? false)
        const _NavItemData(
          label: 'My Interviews',
          icon: Icons.event_note_rounded,
          path: '/interviews',
          accent: AppColors.primary,
          isPush: true,
        ),
      if (user?.hasPermission('REQUISITION_CREATE') ?? false)
        const _NavItemData(
          label: 'Job Requisitions',
          icon: Icons.work_outline_rounded,
          path: '/requisitions',
          accent: AppColors.pink,
          isPush: true,
        ),
      _NavItemData(
        label: 'Announcements',
        icon: Icons.campaign_rounded,
        path: '/announcements',
        accent: AppColors.primary,
        badge: unreadAnnouncements > 0 ? unreadAnnouncements : null,
        isPush: true,
      ),
      _NavItemData(
        label: 'Policies',
        icon: Icons.description_rounded,
        path: '/policies',
        accent: AppColors.info,
        badge: unreadPolicies > 0 ? unreadPolicies : null,
        isPush: true,
      ),
      const _NavItemData(
        label: 'My Meetings',
        icon: Icons.event_rounded,
        path: '/my-meetings',
        accent: AppColors.primary,
        isPush: true,
      ),
      const _NavItemData(
        label: 'My Trainings',
        icon: Icons.school_rounded,
        path: '/my-trainings',
        accent: AppColors.warning,
        isPush: true,
      ),
      const _NavItemData(
        label: 'My Assets',
        icon: Icons.devices_other_rounded,
        path: '/assets',
        accent: AppColors.primary,
        isPush: true,
      ),
      const _NavItemData(
        label: 'My Payslips',
        icon: Icons.receipt_long_rounded,
        path: '/my-payslips',
        accent: AppColors.success,
        isPush: true,
      ),
      const _NavItemData(
        label: 'My Resignation',
        icon: Icons.logout_rounded,
        path: '/my-resignation',
        accent: AppColors.danger,
        isPush: true,
      ),
    ];

    // Local fuzzy filter on label.
    final query = _query.trim().toLowerCase();
    bool matches(_NavItemData item) =>
        query.isEmpty || item.label.toLowerCase().contains(query);
    final filteredOverview = overviewItems.where(matches).toList();
    final filteredWorkspace = workspaceItems.where(matches).toList();

    return Drawer(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: GlassBackdrop(
        intensity: 1.1,
        child: ClipRRect(
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(28),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  right: BorderSide(color: AppColors.hairline),
                ),
              ),
              child: Column(
                children: [
                  SizedBox(height: mq.padding.top + 10),
                  _DrawerBrandRow(
                    onClose: () => Navigator.pop(context),
                    onOpenProfile: () {
                      Navigator.pop(context);
                      context.push('/profile');
                    },
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                    child: _DrawerSearchField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      children: [
                        if (filteredOverview.isNotEmpty) ...[
                          const _DrawerSectionLabel(label: 'OVERVIEW'),
                          for (final item in filteredOverview)
                            _DrawerNavTile(
                              item: item,
                              currentPath: widget.currentPath,
                            ),
                        ],
                        if (filteredWorkspace.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          const _DrawerSectionLabel(label: 'WORKSPACE'),
                          for (final item in filteredWorkspace)
                            _DrawerNavTile(
                              item: item,
                              currentPath: widget.currentPath,
                            ),
                        ],
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      0,
                      12,
                      mq.padding.bottom + 12,
                    ),
                    child: _DrawerUserCard(
                      name: user?.username ?? 'User',
                      email: user?.email ?? '',
                      role: user?.role ?? 'EMPLOYEE',
                      onSignOut: () {
                        // Capture the notifier BEFORE popping the drawer — once
                        // the drawer is popped this State (and its `ref`) is
                        // disposed, so reading `ref` later would throw. The
                        // notifier itself lives in the ProviderContainer and is
                        // safe to use afterwards.
                        final auth =
                            ref.read(authControllerProvider.notifier);
                        Navigator.pop(context);
                        _showLogoutDialog(context, auth);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, AuthController auth) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white.withOpacity(0.92),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        title: const Text(
          'Sign out?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'You will need to sign in again to access your workspace.',
          style: TextStyle(color: AppColors.inkSoft, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              Navigator.pop(ctx);
              auth.logout();
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Brand row (top of drawer)
// ─────────────────────────────────────────────────────────────────────

class _DrawerBrandRow extends ConsumerWidget {
  const _DrawerBrandRow({required this.onClose, required this.onOpenProfile});
  final VoidCallback onClose;
  final VoidCallback onOpenProfile;

  String _formatEmployeeCode(int? id) {
    if (id == null) return 'Not linked';
    return 'EMP-${id.toString().padLeft(4, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider);
    
    final profileAsync = user?.employeeId != null
        ? ref.watch(employeeProfileProvider(user!.employeeId!))
        : null;
    final profile = profileAsync?.value;
    
    final rawCode = profile != null ? profile['employeeCode'] as String? : null;
    final code = rawCode != null && rawCode.isNotEmpty
        ? rawCode
        : _formatEmployeeCode(user?.employeeId);
        
    // Name comes from the cached login user — shown instantly, no API wait.
    final name = user?.displayName ?? 'User';

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: Row(
        children: [
          // Tappable employee chip → profile.
          Expanded(
            child: Semantics(
              button: true,
              label: 'View profile for $name, employee code $code',
              child: Material(
                color: Colors.white.withOpacity(0.35),
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onOpenProfile,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.55),
                      ),
                    ),
                    child: Row(
                      children: [
                        UserAvatar(name: name, size: 36, radius: 10),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink,
                                  letterSpacing: 0.1,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                code,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.muted,
                                  letterSpacing: 0.3,
                                  fontFeatures: [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: AppColors.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Close — icon-only, accessible label.
          Semantics(
            button: true,
            label: 'Close navigation drawer',
            child: SizedBox(
              width: 36,
              height: 36,
              child: Material(
                color: Colors.white.withOpacity(0.55),
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onClose,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.55),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Search field (filters nav items locally)
// ─────────────────────────────────────────────────────────────────────

class _DrawerSearchField extends StatelessWidget {
  const _DrawerSearchField({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44, // touch target ≥44px
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: Colors.white.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Icon(
            Icons.search_rounded,
            size: 17,
            color: AppColors.muted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              cursorColor: AppColors.primary,
              cursorWidth: 1.5,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.ink,
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                isCollapsed: true,
                contentPadding: EdgeInsets.symmetric(vertical: 13),
                border: InputBorder.none,
                hintText: 'Search workspace…',
                hintStyle: TextStyle(
                  color: AppColors.muted,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                splashRadius: 16,
                visualDensity: VisualDensity.compact,
                tooltip: 'Clear search',
                icon: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppColors.muted,
                ),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Section header label (uppercase, muted)
// ─────────────────────────────────────────────────────────────────────

class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
          color: AppColors.muted,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Nav tile with optional badge + active accent bar
// ─────────────────────────────────────────────────────────────────────

class _DrawerNavTile extends StatelessWidget {
  const _DrawerNavTile({
    required this.item,
    required this.currentPath,
  });

  final _NavItemData item;
  final String currentPath;

  bool get _isActive => currentPath.startsWith(item.path);

  @override
  Widget build(BuildContext context) {
    final color = item.accent ?? AppColors.primary;
    final isActive = _isActive;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.md),
          onTap: () {
            Navigator.pop(context);
            if (item.isPush) {
              context.push(item.path);
            } else {
              context.go(item.path);
            }
          },
          child: Container(
            decoration: BoxDecoration(
              gradient: isActive
                  ? LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        color.withOpacity(0.18),
                        color.withOpacity(0.06),
                      ],
                    )
                  : null,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(
                color: isActive
                    ? color.withOpacity(0.28)
                    : Colors.transparent,
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  // 3px left accent bar — visible only when active.
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 3,
                    height: 22,
                    margin: const EdgeInsets.only(left: 4, right: 7),
                    decoration: BoxDecoration(
                      color: isActive ? color : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      gradient: isActive
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                color.withOpacity(0.30),
                                color.withOpacity(0.16),
                              ],
                            )
                          : null,
                      color: isActive
                          ? null
                          : Colors.white.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: isActive
                            ? color.withOpacity(0.30)
                            : Colors.white.withOpacity(0.55),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      item.icon,
                      size: 17,
                      color: isActive ? color : AppColors.muted,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w600,
                        color: isActive ? color : AppColors.inkSoft,
                      ),
                    ),
                  ),
                  if (item.badge != null && item.badge! > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _DrawerBadge(
                        value: item.badge!,
                        asString: item.badgeAsString,
                        tone: color,
                      ),
                    )
                  else
                    const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Badge — numeric (ring tint) or string-style "New" (emerald)
// ─────────────────────────────────────────────────────────────────────

class _DrawerBadge extends StatelessWidget {
  const _DrawerBadge({
    required this.value,
    required this.asString,
    required this.tone,
  });

  final int value;
  final bool asString;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final isStringStyle = asString;
    final color = isStringStyle ? AppColors.success : tone;
    final label = isStringStyle ? 'New' : (value > 99 ? '99+' : '$value');

    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color.withOpacity(0.32)),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Footer link (small, muted)
// ─────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────
// User card at the bottom (avatar + status dot + name/email + sign-out)
// ─────────────────────────────────────────────────────────────────────

class _DrawerUserCard extends StatelessWidget {
  const _DrawerUserCard({
    required this.name,
    required this.email,
    required this.role,
    required this.onSignOut,
  });

  final String name;
  final String email;
  final String role;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
      shadow: AppShadows.soft,
      child: Row(
        children: [
          // Avatar with online status dot.
          Stack(
            clipBehavior: Clip.none,
            children: [
              UserAvatar(name: name, size: 38, radius: 11),
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.25),
                        ),
                      ),
                      child: Text(
                        role,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  email.isEmpty ? 'Signed in' : email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Semantics(
            button: true,
            label: 'Sign out',
            child: SizedBox(
              width: 36,
              height: 36,
              child: Material(
                color: AppColors.danger.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onSignOut,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.danger.withOpacity(0.30),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.logout_rounded,
                      size: 17,
                      color: AppColors.danger.withOpacity(0.85),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Bottom nav item
// ─────────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary.withOpacity(0.18),
                      AppColors.accent.withOpacity(0.18),
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: selected
                ? Border.all(color: AppColors.primary.withOpacity(0.28))
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: selected ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: Icon(
                  selected ? tab.selectedIcon : tab.icon,
                  size: 20,
                  color: selected ? AppColors.primary : AppColors.muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                tab.label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? AppColors.primary : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;
  const _Tab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.path,
  });
}
