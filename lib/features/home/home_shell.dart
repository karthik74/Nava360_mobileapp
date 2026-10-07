import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/branding.dart';
import '../../core/navigation/mobile_menu_config.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../announcements/announcements_repository.dart';
import '../policies/policies_repository.dart';
import '../attendance/sign_out_guard.dart';
import '../auth/auth_controller.dart';
import '../chat/chat_controller.dart';
import '../leaves/leave_repository.dart';
import '../tasks/task_repository.dart';

// ─────────────────────────────────────────────────────────────────────
// Drawer presentation styles (all driven by the same mobile_menu_config):
//   collapsible — #1: expandable module sections, menus inline.
//   moduleList  — #2: module cards → each opens a dedicated module screen.
// (chips — #3 — will be added when implemented.) Flip this one variable to
// switch the drawer between implementations.
// ─────────────────────────────────────────────────────────────────────
enum _DrawerStyle { collapsible, moduleList }

// `final` (not `const`) on purpose: it keeps BOTH branches live for the
// analyzer, so the inactive style's code is never flagged as dead.
// collapsible = everything stays IN the drawer (tap a module → its menus
// expand inline, no new screen). moduleList = module cards → dedicated screens.
// ignore: prefer_const_declarations
final _DrawerStyle _kDrawerStyle = _DrawerStyle.collapsible;

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

  // Bottom-nav tabs are sourced from mobile_menu_config.dart (bottomNavTabs).

  int _indexFromLocation(String loc, List<_Tab> tabs) {
    for (var i = 0; i < tabs.length; i++) {
      if (loc.startsWith(tabs[i].path)) return i;
    }
    // A shell route that isn't one of the visible tabs (e.g. /leaves opened
    // from the drawer) — highlight none rather than Home.
    return -1;
  }

  String _titleFor(String loc) {
    if (loc.startsWith('/home')) return 'Dashboard';
    if (loc.startsWith('/attendance')) return 'Attendance';
    if (loc.startsWith('/leaves')) return 'Leaves';
    if (loc.startsWith('/tasks')) return 'Tasks';
    if (loc.startsWith('/chats')) return 'Chats';
    if (loc.startsWith('/team')) return 'Team';
    if (loc.startsWith('/performance')) return 'Performance';
    return Branding.current.productName;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = GoRouterState.of(context).matchedLocation;
    final user = ref.watch(authUserProvider);
    final isManager = isManagerUser(user);
    // Bottom-nav tabs come from the centralized mobile_menu_config (Home, HRMS,
    // Payroll, My Team*, More — My Team only for managers). No hardcoded tabs.
    final visibleTabs = bottomNavTabs(user)
        .map((m) => _Tab(label: m.label, icon: m.icon, selectedIcon: m.icon, path: m.route))
        .toList();
    final index = _indexFromLocation(loc, visibleTabs);

    return PopScope(
      // On a root tab, intercept Android back → go Home instead of exiting;
      // deeper (pushed) screens pop normally because the shell isn't the top route.
      canPop: index <= 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/home');
      },
      child: Scaffold(
      key: const ValueKey('home_shell_scaffold'),
      backgroundColor: Colors.transparent,
      extendBody: true,
      extendBodyBehindAppBar: true,
      drawer: _AppDrawer(currentPath: loc, isManager: isManager),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(
          MediaQuery.of(context).padding.top + AppChrome.appBarHeight,
        ),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Container(
            color: AppColors.deep,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
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
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: AppColors.live.withOpacity(0.9),
                            width: 1.5,
                          ),
                        ),
                        child: UserAvatar(
                          name: user?.username ?? '',
                          size: 34,
                          radius: 10,
                        ),
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            user?.username ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // AI Assistant lives here (top-right of the shell
                    // header, every tab), not in the menu list.
                    if (ref
                        .watch(brandingProvider)
                        .featureEnabled('FEATURE_AI_ASSISTANT'))
                      _AssistantButton(
                          onTap: () => context.push('/assistant')),
                  ],
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
      bottomNavigationBar: loc.startsWith('/attendance')
          ? null
          : _FloatingTabBar(
              tabs: visibleTabs,
              index: index,
              onTap: (i) => context.go(visibleTabs[i].path),
            ),
      ),
    );
  }
}

/// Top-right AI Assistant entry point on the Home tab — a small gradient
/// sparkle button (the assistant has no menu-list entry).
class _AssistantButton extends StatelessWidget {
  const _AssistantButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'AI Assistant',
      child: _ShellIconButton(
        icon: Icons.auto_awesome_rounded,
        onTap: onTap,
        iconColor: AppColors.live,
      ),
    );
  }
}

class _HamburgerButton extends StatelessWidget {
  const _HamburgerButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open menu',
      child: _ShellIconButton(icon: Icons.menu_rounded, onTap: onTap),
    );
  }
}

/// 40×40 translucent square for the deep shell header.
class _ShellIconButton extends StatelessWidget {
  const _ShellIconButton({
    required this.icon,
    required this.onTap,
    this.iconColor = Colors.white,
  });
  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withOpacity(0.14)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 19, color: iconColor),
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
    this.badge,
    this.badgeAsString = false,
    this.isPush = false,
  });

  final String label;
  final IconData icon;
  final String path;

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
    // Menu visibility reads the server feature flags; rebuild when the background
    // branding refresh lands so a flag switched on shows without an app restart.
    ref.watch(brandingProvider);
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

    final unreadChats = ref.watch(totalUnreadProvider);

    // Live badges keyed by route, applied to the config-driven items below.
    final badges = <String, int>{
      '/leaves': pendingLeaves,
      '/tasks': activeTasks,
      '/chats': unreadChats,
      '/team': pendingApprovals,
      '/announcements': unreadAnnouncements,
      '/policies': unreadPolicies,
    };
    // Routes hosted by the bottom-nav ShellRoute navigate with `go` (switch tab);
    // everything else pushes so the back button returns to the previous screen.
    const tabRoutes = {'/home', '/attendance', '/leaves', '/tasks', '/chats', '/team', '/performance', '/hrms', '/payroll', '/more'};

    Color moduleAccent(MobileModule m) {
      switch (m) {
        case MobileModule.hrms:
          return AppColors.primary;
        case MobileModule.payroll:
          return AppColors.success;
        case MobileModule.team:
          return AppColors.pink;
        case MobileModule.mis:
          return AppColors.warning;
        case MobileModule.more:
          return AppColors.info;
        case MobileModule.home:
          return AppColors.accent;
      }
    }

    // Aggregate badge for a module = sum of its menu items' route badges.
    int moduleBadge(MobileModule m) =>
        menuFor(m, user).fold(0, (s, item) => s + (badges[item.route] ?? 0));

    // Items for a module — deduped by route (collapses stubbed Payroll/Team
    // sub-cards to one entry per destination).
    List<_NavItemData> itemsForModule(MobileModule module) {
      final seen = <String>{};
      final out = <_NavItemData>[];
      for (final m in menuFor(module, user)) {
        if (!seen.add(m.route)) continue;
        final b = badges[m.route] ?? 0;
        out.add(_NavItemData(
          label: m.label,
          icon: m.icon,
          path: m.route,
          badge: b > 0 ? b : null,
          isPush: !tabRoutes.contains(m.route),
        ));
      }
      return out;
    }

    // Collapsible module sections (Home is the bottom-nav tab — surfaced as a
    // direct Dashboard tile above, not a section).
    final moduleSections = modulesFor(user)
        .where((mi) => mi.module != MobileModule.home)
        .map((mi) => (info: mi, items: itemsForModule(mi.module)))
        .where((s) => s.items.isNotEmpty)
        .toList();
    final anyActive = moduleSections
        .any((s) => s.items.any((i) => widget.currentPath.startsWith(i.path)));

    // When the user types, search jumps straight to any menu across all modules.
    final query = _query.trim().toLowerCase();
    final searchItems = query.isEmpty
        ? <_NavItemData>[]
        : allMenuItems(user)
            .where((m) => m.label.toLowerCase().contains(query))
            .map((m) {
              final b = badges[m.route] ?? 0;
              return _NavItemData(
                label: m.label,
                icon: m.icon,
                path: m.route,
                badge: b > 0 ? b : null,
                isPush: !tabRoutes.contains(m.route),
              );
            })
            .toList();

    return Drawer(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      width: math.min(mq.size.width * 0.86, 340),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Deep header continues the shell app bar: who you are + search.
          AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: Container(
              color: AppColors.deep,
              padding: EdgeInsets.fromLTRB(0, mq.padding.top + 10, 0, 14),
              child: Column(
                children: [
                  _DrawerBrandRow(
                    onClose: () => Navigator.pop(context),
                    onOpenProfile: () {
                      Navigator.pop(context);
                      context.push('/profile');
                    },
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: _DrawerSearchField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              children: [
                // Implementation #1 — collapsible module sections.
                if (query.isEmpty &&
                    _kDrawerStyle == _DrawerStyle.collapsible) ...[
                  _DrawerNavTile(
                    item: const _NavItemData(
                      label: 'Dashboard',
                      icon: Icons.home_rounded,
                      path: '/home',
                    ),
                    currentPath: widget.currentPath,
                  ),
                  const _DrawerSectionLabel(label: 'MODULES'),
                  for (var s = 0; s < moduleSections.length; s++)
                    _ModuleSection(
                      label: moduleSections[s].info.label,
                      icon: moduleSections[s].info.icon,
                      accent: moduleAccent(moduleSections[s].info.module),
                      badge: moduleBadge(moduleSections[s].info.module),
                      items: moduleSections[s].items,
                      currentPath: widget.currentPath,
                      initiallyExpanded: moduleSections[s].items.any(
                              (i) => widget.currentPath.startsWith(i.path)) ||
                          (!anyActive && s == 0),
                    ),
                ]
                // Implementation #2 — module list (cards) → module screen.
                else if (query.isEmpty &&
                    _kDrawerStyle == _DrawerStyle.moduleList) ...[
                  const _DrawerSectionLabel(label: 'MODULES'),
                  for (final mi in modulesFor(user)
                      .where((m) => m.module != MobileModule.home))
                    _ModuleCard(
                      label: mi.label,
                      icon: mi.icon,
                      accent: moduleAccent(mi.module),
                      badge: moduleBadge(mi.module),
                      itemCount: itemsForModule(mi.module).length,
                      active: widget.currentPath.startsWith(mi.route) ||
                          itemsForModule(mi.module)
                              .any((i) => widget.currentPath.startsWith(i.path)),
                      // Push (not go) so the system Back returns to the
                      // previous screen — predictable drawer navigation.
                      onTap: () {
                        Navigator.pop(context);
                        context.push(mi.route);
                      },
                    ),
                ] else if (searchItems.isEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 28, 16, 8),
                    child: Column(
                      children: [
                        const Icon(Icons.search_off_rounded,
                            size: 28, color: AppColors.faint),
                        const SizedBox(height: 8),
                        Text(
                          'No menus match "${_query.trim()}"',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  _DrawerSectionLabel(label: 'RESULTS · ${searchItems.length}'),
                  for (final item in searchItems)
                    _DrawerNavTile(
                      item: item,
                      currentPath: widget.currentPath,
                    ),
                ],
                const SizedBox(height: 12),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.hairline)),
            ),
            padding: EdgeInsets.fromLTRB(14, 12, 10, mq.padding.bottom + 12),
            child: _DrawerUserCard(
              name: user?.username ?? 'User',
              email: user?.email ?? '',
              role: user?.role ?? 'EMPLOYEE',
              onSignOut: () async {
                // The check-in guard reads providers, so it has to run
                // while the drawer — and this State's `ref` — is still
                // alive. Same reason the notifier is captured here.
                final checkedIn = await isCheckedInNow(ref);
                final auth = ref.read(authControllerProvider.notifier);
                if (!context.mounted) return;
                Navigator.pop(context);
                if (checkedIn) {
                  await showCheckOutRequiredDialog(context);
                  return;
                }
                if (context.mounted) {
                  _showLogoutDialog(context, auth);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, AuthController auth) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will need to sign in again to access your workspace.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
            ),
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
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      child: Row(
        children: [
          // Tappable employee chip → profile.
          Expanded(
            child: Semantics(
              button: true,
              label: 'View profile for $name, employee code $code',
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onOpenProfile,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.live.withOpacity(0.9),
                              width: 1.5,
                            ),
                          ),
                          child: UserAvatar(name: name, size: 40, radius: 11),
                        ),
                        const SizedBox(width: 12),
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
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      code,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white.withOpacity(0.62),
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 16,
                                    color: Colors.white.withOpacity(0.5),
                                  ),
                                ],
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
          const SizedBox(width: 8),
          // Close — icon-only, accessible label.
          Semantics(
            button: true,
            label: 'Close navigation drawer',
            child: Material(
              color: Colors.white.withOpacity(0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.white.withOpacity(0.14)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onClose,
                child: const SizedBox(
                  width: 38,
                  height: 38,
                  child: Icon(Icons.close_rounded, size: 18, color: Colors.white),
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
// Search field (filters nav items locally) — translucent on the deep header
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
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(
            Icons.search_rounded,
            size: 18,
            color: Colors.white.withOpacity(0.6),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              cursorColor: AppColors.live,
              cursorWidth: 1.5,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Search menus…',
                hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
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
                icon: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Colors.white.withOpacity(0.7),
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
// Section header label (sentence case, muted)
// ─────────────────────────────────────────────────────────────────────

class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = label.isEmpty
        ? label
        : label[0].toUpperCase() + label.substring(1).toLowerCase();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.muted,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Collapsible module section (Implementation #1) — an expandable header
// (module icon + label + aggregate badge + animated chevron) that reveals
// the module's menu tiles inline on a white card. State is local so each
// module expands independently.
// ─────────────────────────────────────────────────────────────────────
class _ModuleSection extends StatefulWidget {
  const _ModuleSection({
    required this.label,
    required this.icon,
    required this.accent,
    required this.badge,
    required this.items,
    required this.currentPath,
    required this.initiallyExpanded,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final int badge;
  final List<_NavItemData> items;
  final String currentPath;
  final bool initiallyExpanded;

  @override
  State<_ModuleSection> createState() => _ModuleSectionState();
}

class _ModuleSectionState extends State<_ModuleSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: _expanded ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
          color: _expanded ? AppColors.hairline : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: widget.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(widget.icon, size: 18, color: widget.accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.label,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (widget.badge > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _DrawerBadge(
                          value: widget.badge,
                          asString: false,
                          tone: AppColors.primary,
                        ),
                      ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 22,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                    child: Column(
                      children: [
                        for (final item in widget.items)
                          _DrawerNavTile(
                            item: item,
                            currentPath: widget.currentPath,
                            nested: true,
                          ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Module card (Implementation #2) — a tappable card for a top-level module
// (icon + label + menu count + aggregate badge + chevron). Highlights when
// the current route belongs to the module; tapping opens its module screen.
// ─────────────────────────────────────────────────────────────────────
class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.label,
    required this.icon,
    required this.accent,
    required this.badge,
    required this.itemCount,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final int badge;
  final int itemCount;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: BorderSide(
            color: active ? AppColors.primary : AppColors.hairline,
            width: active ? 1.4 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 20, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        itemCount == 1 ? '1 menu' : '$itemCount menus',
                        style: const TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                if (badge > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _DrawerBadge(
                      value: badge,
                      asString: false,
                      tone: AppColors.primary,
                    ),
                  ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: active ? AppColors.primary : AppColors.faint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Nav tile — active = brand tint + brand icon/label
// ─────────────────────────────────────────────────────────────────────

class _DrawerNavTile extends StatelessWidget {
  const _DrawerNavTile({
    required this.item,
    required this.currentPath,
    this.nested = false,
  });

  final _NavItemData item;
  final String currentPath;
  final bool nested;

  bool get _isActive => currentPath.startsWith(item.path);

  @override
  Widget build(BuildContext context) {
    final color = AppColors.primary;
    final isActive = _isActive;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: isActive ? color.withOpacity(0.09) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.pop(context);
            if (item.isPush) {
              context.push(item.path);
            } else {
              context.go(item.path);
            }
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: EdgeInsets.fromLTRB(nested ? 8 : 10, 6, 8, 6),
              child: Row(
                children: [
                  SizedBox(
                    width: nested ? 28 : 34,
                    height: nested ? 28 : 34,
                    child: nested
                        ? Icon(
                            item.icon,
                            size: 18,
                            color: isActive ? color : AppColors.muted,
                          )
                        : DecoratedBox(
                            decoration: BoxDecoration(
                              color: isActive
                                  ? color.withOpacity(0.14)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isActive
                                    ? Colors.transparent
                                    : AppColors.hairline,
                              ),
                            ),
                            child: Icon(
                              item.icon,
                              size: 18,
                              color: isActive ? color : AppColors.inkSoft,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                        color: isActive ? color : AppColors.inkSoft,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                  if (item.badge != null && item.badge! > 0)
                    _DrawerBadge(
                      value: item.badge!,
                      asString: item.badgeAsString,
                      tone: color,
                    )
                  else if (isActive)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
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
}

// ─────────────────────────────────────────────────────────────────────
// Badge — numeric (solid brand pill) or string-style "New" (success)
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
      constraints: const BoxConstraints(minWidth: 22, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// User row at the bottom (avatar + status dot + name/email + sign-out)
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

  String get _roleLabel {
    final r = role.replaceAll('_', ' ').trim();
    if (r.isEmpty) return r;
    return r[0].toUpperCase() + r.substring(1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
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
                  color: AppColors.live,
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
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.neutralTint,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Text(
                      _roleLabel,
                      style: const TextStyle(
                        color: AppColors.inkSoft,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                email.isEmpty ? 'Signed in' : email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Semantics(
          button: true,
          label: 'Sign out',
          child: Material(
            color: AppColors.dangerTint,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onSignOut,
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  Icons.logout_rounded,
                  size: 18,
                  color: AppColors.danger,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Bottom nav item
// ─────────────────────────────────────────────────────────────────────

/// Floating deep capsule tab bar. The active tab expands into a white pill
/// with its label; the others show their icon only.
class _FloatingTabBar extends StatelessWidget {
  const _FloatingTabBar({
    required this.tabs,
    required this.index,
    required this.onTap,
  });

  final List<_Tab> tabs;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + safe),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.deep,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x6604181C),
              blurRadius: 40,
              spreadRadius: -16,
              offset: Offset(0, 20),
            ),
            BoxShadow(
              color: Color(0x3304181C),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final n = tabs.length;
            final grow = index >= 0 ? 2.2 : 1.0;
            final unit = c.maxWidth / (n - 1 + grow);
            return Row(
              children: [
                for (var i = 0; i < n; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutBack,
                    width: i == index ? unit * grow : unit,
                    child: _NavItem(
                      tab: tabs[i],
                      selected: i == index,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onTap(i);
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

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
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            height: 48,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: EdgeInsets.symmetric(horizontal: selected ? 14 : 0),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x80000000),
                        blurRadius: 16,
                        spreadRadius: -8,
                        offset: Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: selected ? 1.0 : 0.94,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutBack,
                  child: Icon(
                    selected ? tab.selectedIcon : tab.icon,
                    size: 21,
                    color: selected ? AppColors.deep : Colors.white.withOpacity(0.62),
                  ),
                ),
                if (selected)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 7),
                      child: Text(
                        tab.label,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                          color: AppColors.deep,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
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
