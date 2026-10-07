import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/branding.dart';
import '../../core/navigation/mobile_menu_config.dart';
import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../announcements/announcements_repository.dart';
import '../policies/policies_repository.dart';
import '../attendance/sign_out_guard.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';
import '../chat/chat_controller.dart';
import '../leaves/leave_repository.dart';
import '../tasks/assign_task_screen.dart';
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

  // Bottom-nav tabs are sourced from mobile_menu_config.dart (bottomNavTabs).

  int _indexFromLocation(String loc, List<_Tab> tabs) {
    for (var i = 0; i < tabs.length; i++) {
      if (loc.startsWith(tabs[i].path)) return i;
    }
    // A shell route that isn't one of the visible tabs (e.g. /leaves opened
    // from the drawer) — highlight none rather than Home.
    return -1;
  }

  /// The centre orb's actions — each only when the user can open that menu.
  List<_QuickAction> _quickActionsFor(BuildContext context, AuthUser? user) {
    final routes = <String>{
      for (final m in allMenuItems(user)) m.route,
      for (final m in bottomNavTabs(user)) m.route,
    };
    final canAssign =
        isManagerUser(user) && (user?.hasPermission('TASK_ASSIGN') ?? false);
    return [
      if (routes.contains('/leaves'))
        _QuickAction('Apply leave', Icons.edit_calendar_rounded,
            AppColors.primary, () => context.go('/leaves')),
      if (routes.contains('/attendance'))
        _QuickAction('Regularise', Icons.history_rounded, AppColors.success,
            () => context.go('/attendance')),
      if (routes.contains('/tasks'))
        canAssign
            ? _QuickAction(
                'Assign task',
                Icons.add_task_rounded,
                const Color(0xFF1D7A4A),
                () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(builder: (_) => const AssignTaskScreen()),
                ),
              )
            : _QuickAction('New task', Icons.add_task_rounded,
                const Color(0xFF1D7A4A), () => context.go('/tasks')),
      if (routes.contains('/travel/claims'))
        _QuickAction('Travel claim', Icons.receipt_long_rounded,
            const Color(0xFFC2571A), () => context.push('/travel/claims/new')),
      if (routes.contains('/helpdesk'))
        _QuickAction('Raise ticket', Icons.support_agent_rounded,
            const Color(0xFF2F18C0), () => context.push('/helpdesk/raise')),
    ];
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
    // Live counts on the tab bar (unread chats, open tasks).
    final tabBadges = <String, int>{
      '/chats': ref.watch(totalUnreadProvider),
      '/tasks': ref.watch(_drawerActiveTasksProvider).asData?.value ?? 0,
    };
    final visibleTabs = bottomNavTabs(user)
        .map((m) => _Tab(
              label: m.label,
              icon: m.icon,
              selectedIcon: m.icon,
              path: m.route,
              badge: tabBadges[m.route] ?? 0,
            ))
        .toList();
    final quickActions = _quickActionsFor(context, user);
    // The design's bar holds two tabs each side of the orb; any further tab
    // moves to the top of the side menu so it stays one tap away.
    final barTabs = visibleTabs.take(4).toList();
    final extraTabs = visibleTabs.skip(4).toList();
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
      drawer: _AppDrawer(
        currentPath: loc,
        isManager: isManager,
        extraTabs: [
          for (final t in extraTabs)
            _NavItemData(
              label: t.label,
              icon: t.icon,
              path: t.path,
              badge: t.badge > 0 ? t.badge : null,
            ),
        ],
      ),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(
          MediaQuery.of(context).padding.top + AppChrome.appBarHeight + 8,
        ),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark,
          child: Container(
            color: AppColors.bg,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Centred title (soft theme), clear of the side buttons.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 96),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _titleFor(loc),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            user?.username ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Builder(
                          builder: (ctx) => _HamburgerButton(
                            onTap: () => Scaffold.of(ctx).openDrawer(),
                          ),
                        ),
                        const Spacer(),
                        // AI Assistant lives here (top-right of the shell
                        // header, every tab), not in the menu list.
                        if (ref
                            .watch(brandingProvider)
                            .featureEnabled('FEATURE_AI_ASSISTANT')) ...[
                          _AssistantButton(
                              onTap: () => context.push('/assistant')),
                          const SizedBox(width: 8),
                        ],
                        Semantics(
                          button: true,
                          label: 'My profile',
                          child: GestureDetector(
                            onTap: () => context.push('/profile'),
                            child: Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: AppShadows.soft,
                              ),
                              child: UserAvatar(
                                name: user?.username ?? '',
                                size: 35,
                                radius: 11.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
              tabs: barTabs,
              index: index < barTabs.length ? index : -1,
              onTap: (i) => context.go(barTabs[i].path),
              onQuickActions: quickActions.isEmpty
                  ? null
                  : () => _showQuickActions(context, quickActions),
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
        onTap: onTap,
        child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => LinearGradient(
            colors: [AppColors.primary, AppColors.glow],
          ).createShader(r),
          child: const Icon(Icons.auto_awesome_rounded, size: 19),
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
    return Semantics(
      button: true,
      label: 'Open menu',
      child: _ShellIconButton(
        onTap: onTap,
        child: const CustomPaint(
          size: Size(18, 12),
          painter: _MenuLinesPainter(),
        ),
      ),
    );
  }
}

/// Two short rounded lines (long over short) — the soft theme's menu glyph.
class _MenuLinesPainter extends CustomPainter {
  const _MenuLinesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.ink
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(1, 2), Offset(size.width - 1, 2), p);
    canvas.drawLine(Offset(1, size.height - 2), Offset(size.width * 0.6, size.height - 2), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 40×40 white rounded square floating on a soft shadow.
class _ShellIconButton extends StatelessWidget {
  const _ShellIconButton({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.soft,
      ),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(width: 40, height: 40, child: Center(child: child)),
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
  const _AppDrawer({
    required this.currentPath,
    required this.isManager,
    this.extraTabs = const [],
  });
  final String currentPath;
  final bool isManager;

  /// Bottom-nav tabs that don't fit on the bar (shown under Dashboard).
  final List<_NavItemData> extraTabs;

  @override
  ConsumerState<_AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<_AppDrawer> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  /// Module tiles (grid) vs collapsible sections (list).
  bool _grid = true;

  /// Module opened from the grid — its menus replace the grid in place.
  MobileModule? _open;

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

    // Drill-down: a module opened from the grid shows its menus in place.
    final openSection = _open == null
        ? null
        : moduleSections.where((s) => s.info.module == _open).firstOrNull;

    return Drawer(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      width: math.min(mq.size.width * 0.88, 360),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Column(
          children: [
            SizedBox(height: mq.padding.top + 12),
            _DrawerBrandRow(
              onClose: () => Navigator.pop(context),
              onOpenProfile: () {
                Navigator.pop(context);
                context.push('/profile');
              },
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _DrawerSearchField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (c, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.04, 0),
                      end: Offset.zero,
                    ).animate(a),
                    child: c,
                  ),
                ),
                child: ListView(
                  key: ValueKey(query.isNotEmpty
                      ? 'search'
                      : openSection != null
                          ? 'module-${openSection.info.module.name}'
                          : 'home-$_grid'),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  children: [
                    if (query.isNotEmpty) ...[
                      _DrawerSectionLabel(
                          label: 'Results · ${searchItems.length}'),
                      if (searchItems.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
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
                        )
                      else
                        _DrawerGroup(children: [
                          for (final item in searchItems)
                            _DrawerNavTile(
                              item: item,
                              currentPath: widget.currentPath,
                            ),
                        ]),
                    ] else if (openSection != null) ...[
                      _DrawerModuleHeader(
                        label: openSection.info.label,
                        icon: openSection.info.icon,
                        accent: moduleAccent(openSection.info.module),
                        count: openSection.items.length,
                        onBack: () => setState(() => _open = null),
                      ),
                      const SizedBox(height: 14),
                      _DrawerGroup(children: [
                        for (final item in openSection.items)
                          _DrawerNavTile(
                            item: item,
                            currentPath: widget.currentPath,
                            accent: moduleAccent(openSection.info.module),
                          ),
                      ]),
                    ] else ...[
                      _DrawerDashboardTile(
                        active: widget.currentPath.startsWith('/home'),
                        onTap: () {
                          Navigator.pop(context);
                          context.go('/home');
                        },
                      ),
                      if (widget.extraTabs.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _DrawerGroup(children: [
                          for (final t in widget.extraTabs)
                            _DrawerNavTile(item: t, currentPath: widget.currentPath),
                        ]),
                      ],
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Your modules',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          _ViewToggle(
                            grid: _grid,
                            onChanged: (g) => setState(() => _grid = g),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_grid)
                        GridView.count(
                          padding: EdgeInsets.zero,
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.06,
                          children: [
                            for (final sec in moduleSections)
                              _ModuleTile(
                                label: sec.info.label,
                                icon: sec.info.icon,
                                accent: moduleAccent(sec.info.module),
                                badge: moduleBadge(sec.info.module),
                                itemCount: sec.items.length,
                                active: sec.items.any(
                                    (i) => widget.currentPath.startsWith(i.path)),
                                onTap: () =>
                                    setState(() => _open = sec.info.module),
                              ),
                          ],
                        )
                      else
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
                    ],
                  ],
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x122A2470),
                    blurRadius: 24,
                    offset: Offset(0, -6),
                  ),
                ],
              ),
              padding: EdgeInsets.fromLTRB(16, 14, 12, mq.padding.bottom + 14),
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
    final first = name.trim().split(RegExp(r'\s+')).first;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: 'View profile for $name, employee code $code',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onOpenProfile,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: AppShadows.soft,
                      ),
                      child: UserAvatar(name: name, size: 42, radius: 13),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Hello $first,',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            code,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.muted,
                              fontFeatures: [FontFeature.tabularFigures()],
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
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'Close navigation drawer',
            child: _DrawerSquareButton(
              icon: Icons.close_rounded,
              onTap: onClose,
            ),
          ),
        ],
      ),
    );
  }
}

/// White rounded square icon button on a soft shadow.
class _DrawerSquareButton extends StatelessWidget {
  const _DrawerSquareButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        boxShadow: AppShadows.soft,
      ),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 19, color: AppColors.ink),
          ),
        ),
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
      height: 46, // touch target ≥44px
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.search_rounded, size: 19, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              cursorColor: AppColors.primary,
              cursorWidth: 1.5,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.ink,
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                isCollapsed: true,
                filled: false,
                contentPadding: EdgeInsets.symmetric(vertical: 13),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Search menus…',
                hintStyle: TextStyle(
                  color: AppColors.faint,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              splashRadius: 16,
              visualDensity: VisualDensity.compact,
              tooltip: 'Clear search',
              icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.muted),
              onPressed: () {
                controller.clear();
                onChanged('');
              },
            )
          else
            const SizedBox(width: 10),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Section label (sentence case)
// ─────────────────────────────────────────────────────────────────────

class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.muted,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Dashboard tile — a small gradient panel at the top of the menu
// ─────────────────────────────────────────────────────────────────────

class _DrawerDashboardTile extends StatelessWidget {
  const _DrawerDashboardTile({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: 'Dashboard',
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: AppColors.deep.withOpacity(0.3),
                blurRadius: 24,
                spreadRadius: -10,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ProDeepSurface(
            radius: 22,
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.space_dashboard_rounded,
                      size: 21, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Dashboard',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        'Your day at a glance',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    active ? Icons.check_rounded : Icons.arrow_forward_rounded,
                    size: 17,
                    color: AppColors.deep,
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

// ─────────────────────────────────────────────────────────────────────
// Grid / list switch (two small squares, like the reference "Your lessons")
// ─────────────────────────────────────────────────────────────────────

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.grid, required this.onChanged});
  final bool grid;
  final ValueChanged<bool> onChanged;

  Widget _btn(IconData icon, bool on, VoidCallback tap, String label) {
    return Semantics(
      button: true,
      selected: on,
      label: label,
      child: GestureDetector(
        onTap: tap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: on ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: on ? AppShadows.soft : null,
          ),
          child: Icon(icon, size: 18, color: on ? AppColors.primary : AppColors.faint),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _btn(Icons.grid_view_rounded, grid, () => onChanged(true), 'Grid view'),
        const SizedBox(width: 6),
        _btn(Icons.view_agenda_outlined, !grid, () => onChanged(false), 'List view'),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Module tile (grid) — gradient icon inside a progress-style ring
// ─────────────────────────────────────────────────────────────────────

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
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
    return Semantics(
      button: true,
      label: '$label, $itemCount menus${badge > 0 ? ', $badge pending' : ''}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: AppShadows.card,
        ),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: active
                ? BorderSide(color: AppColors.primary.withOpacity(0.5), width: 1.4)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ProRingIcon(icon: icon, color: accent),
                      const Spacer(),
                      if (badge > 0)
                        _DrawerBadge(value: badge, asString: false, tone: accent),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    itemCount == 1 ? '1 menu' : '$itemCount menus',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
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
// Opened module header (drill-down from the grid)
// ─────────────────────────────────────────────────────────────────────

class _DrawerModuleHeader extends StatelessWidget {
  const _DrawerModuleHeader({
    required this.label,
    required this.icon,
    required this.accent,
    required this.count,
    required this.onBack,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final int count;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Semantics(
          button: true,
          label: 'All modules',
          child: _DrawerSquareButton(
            icon: Icons.chevron_left_rounded,
            onTap: onBack,
          ),
        ),
        const SizedBox(width: 12),
        ProRingIcon(icon: icon, color: accent, size: 44),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  letterSpacing: -0.4,
                ),
              ),
              Text(
                count == 1 ? '1 menu' : '$count menus',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// White rounded card holding nav rows separated by soft dividers.
class _DrawerGroup extends StatelessWidget {
  const _DrawerGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 60,
                color: AppColors.hairlineSoft,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Collapsible module section (list view) — white card that expands to show
// the module's menus inline. State is local so each module expands
// independently.
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    ProRingIcon(icon: widget.icon, color: widget.accent, size: 40),
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
                          tone: widget.accent,
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
                ? Column(
                    children: [
                      const Divider(height: 1, thickness: 1, color: AppColors.hairlineSoft),
                      for (final item in widget.items)
                        _DrawerNavTile(
                          item: item,
                          currentPath: widget.currentPath,
                          accent: widget.accent,
                          nested: true,
                        ),
                      const SizedBox(height: 4),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Nav row — icon tile + label; active = brand tint + brand label
// ─────────────────────────────────────────────────────────────────────

class _DrawerNavTile extends StatelessWidget {
  const _DrawerNavTile({
    required this.item,
    required this.currentPath,
    this.accent,
    this.nested = false,
  });

  final _NavItemData item;
  final String currentPath;
  final Color? accent;
  final bool nested;

  bool get _isActive => currentPath.startsWith(item.path);

  @override
  Widget build(BuildContext context) {
    final brand = AppColors.primary;
    final tone = accent ?? brand;
    final isActive = _isActive;

    return Material(
      color: isActive ? brand.withOpacity(0.07) : Colors.transparent,
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
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: EdgeInsets.fromLTRB(nested ? 18 : 12, 7, 12, 7),
            child: Row(
              children: [
                if (nested)
                  SizedBox(
                    width: 32,
                    child: Icon(item.icon, size: 19, color: isActive ? brand : AppColors.muted),
                  )
                else
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [tone.withOpacity(0.18), tone.withOpacity(0.07)],
                      ),
                    ),
                    child: Icon(item.icon, size: 18, color: tone),
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
                      color: isActive ? brand : AppColors.ink,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                if (item.badge != null && item.badge! > 0)
                  _DrawerBadge(
                    value: item.badge!,
                    asString: item.badgeAsString,
                    tone: brand,
                  )
                else
                  Icon(
                    isActive ? Icons.circle : Icons.chevron_right_rounded,
                    size: isActive ? 7 : 20,
                    color: isActive ? brand : AppColors.faint,
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
// Badge — numeric (solid pill) or string-style "New" (success)
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
        Stack(
          clipBehavior: Clip.none,
          children: [
            UserAvatar(name: name, size: 38, radius: 12),
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
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Text(
                      _roleLabel,
                      style: TextStyle(
                        color: AppColors.primary,
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
            borderRadius: BorderRadius.circular(13),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onSignOut,
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.logout_rounded, size: 18, color: AppColors.danger),
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

/// Floating white tab bar with a raised glossy quick-action orb sitting in a
/// curved notch — the HTML design's `.bnav` + `.bn-fab`. The active tab is a
/// brand-tinted pill with its label (when there is room); tabs can carry a
/// red count badge.
class _FloatingTabBar extends StatelessWidget {
  const _FloatingTabBar({
    required this.tabs,
    required this.index,
    required this.onTap,
    this.onQuickActions,
  });

  final List<_Tab> tabs;
  final int index;
  final ValueChanged<int> onTap;

  /// Opens the quick-actions arc; null hides the centre orb.
  final VoidCallback? onQuickActions;

  static const double barHeight = 68;
  static const double _slot = 70;

  Widget _half(List<int> items) {
    return LayoutBuilder(
      builder: (context, c) {
        final active = items.contains(index);
        const grow = 2.4;
        final unit = c.maxWidth / (items.length - (active ? 1 : 0) + (active ? grow : 0));
        return Row(
          children: [
            for (final i in items)
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).padding.bottom;
    final hasOrb = onQuickActions != null;
    final split = hasOrb ? (tabs.length / 2).ceil() : tabs.length;
    final left = [for (var i = 0; i < split; i++) i];
    final right = [for (var i = split; i < tabs.length; i++) i];

    return Padding(
      padding: EdgeInsets.fromLTRB(10, 0, 10, 10 + safe),
      child: SizedBox(
        height: barHeight + (hasOrb ? 34 : 0),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: barHeight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x6B2A2470),
                      blurRadius: 40,
                      spreadRadius: -18,
                      offset: Offset(0, 20),
                    ),
                    BoxShadow(
                      color: Color(0x122A2470),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: hasOrb
                    ? Row(
                        children: [
                          Expanded(child: _half(left)),
                          const SizedBox(width: _slot),
                          Expanded(child: _half(right)),
                        ],
                      )
                    : _half(left),
              ),
            ),
            if (hasOrb) ...[
              // Curved notch the orb sits in.
              const Positioned(
                bottom: barHeight - 5,
                child: CustomPaint(size: Size(136, 26), painter: _BumpPainter()),
              ),
              Positioned(
                bottom: barHeight - 38 - 9,
                child: _QuickOrb(onTap: onQuickActions!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The white bump: `M0 26 C 28 26, 34 1, 68 1 C 102 1, 108 26, 136 26 Z`.
class _BumpPainter extends CustomPainter {
  const _BumpPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 136, sy = size.height / 26;
    final path = Path()
      ..moveTo(0, 26 * sy)
      ..cubicTo(28 * sx, 26 * sy, 34 * sx, 1 * sy, 68 * sx, 1 * sy)
      ..cubicTo(102 * sx, 1 * sy, 108 * sx, 26 * sy, 136 * sx, 26 * sy)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Glossy brand orb (62) inside a slowly turning dashed ring with an
/// orbiting dot. [open] turns it white with an × (used by the overlay).
class _QuickOrb extends StatefulWidget {
  const _QuickOrb({required this.onTap, this.open = false});
  final VoidCallback onTap;
  final bool open;

  @override
  State<_QuickOrb> createState() => _QuickOrbState();
}

class _QuickOrbState extends State<_QuickOrb> with TickerProviderStateMixin {
  late final AnimationController _ring =
      AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();
  late final AnimationController _dot = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.open ? 1300 : 4500),
  )..repeat();

  @override
  void dispose() {
    _ring.dispose();
    _dot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = AppColors.primary;
    return Semantics(
      button: true,
      label: widget.open ? 'Close quick actions' : 'Quick actions',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        child: RepaintBoundary(
          child: SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Rotations only move cached layers — no per-frame repaint.
                RotationTransition(
                  turns: _ring,
                  child: CustomPaint(
                    size: const Size(80, 80),
                    painter: _DashedRingPainter(brand.withOpacity(0.3)),
                  ),
                ),
                RotationTransition(
                  turns: _dot,
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 0),
                        decoration: BoxDecoration(
                          color: brand,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: brand.withOpacity(0.2), spreadRadius: 3),
                            BoxShadow(color: brand.withOpacity(0.6), blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.open ? Colors.white : null,
                    gradient: widget.open
                        ? null
                        : LinearGradient(
                            begin: const Alignment(-0.6, -0.9),
                            end: const Alignment(0.6, 0.9),
                            colors: [
                              Color.lerp(brand, Colors.white, 0.32)!,
                              brand,
                              Color.lerp(brand, Colors.black, 0.2)!,
                            ],
                            stops: const [0, 0.62, 1],
                          ),
                    boxShadow: [
                      BoxShadow(
                        color: brand.withOpacity(widget.open ? 0.35 : 0.75),
                        blurRadius: 28,
                        spreadRadius: -12,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  foregroundDecoration: widget.open
                      ? null
                      : BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            center: const Alignment(-0.36, -0.52),
                            radius: 0.62,
                            colors: [
                              Colors.white.withOpacity(0.85),
                              Colors.white.withOpacity(0),
                            ],
                            stops: const [0, 0.5],
                          ),
                        ),
                  child: AnimatedRotation(
                    turns: widget.open ? 0.375 : 0,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutBack,
                    child: Icon(
                      Icons.add_rounded,
                      size: 30,
                      color: widget.open ? brand : Colors.white,
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

class _DashedRingPainter extends CustomPainter {
  _DashedRingPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 1;
    final c = size.center(Offset.zero);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    const dashes = 28;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), i * sweep, sweep * 0.55, false, p);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRingPainter old) => old.color != color;
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
    final brand = AppColors.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.badge > 0 ? '${tab.label}, ${tab.badge} pending' : tab.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, c) {
            // Label only when the active pill has room for it.
            final showLabel = selected && c.maxWidth >= 78;
            return Center(
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    height: 48,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: EdgeInsets.symmetric(horizontal: showLabel ? 10 : 0),
                    decoration: BoxDecoration(
                      color: selected ? brand.withOpacity(0.11) : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
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
                            size: 22,
                            color: selected ? brand : AppColors.muted,
                          ),
                        ),
                        if (showLabel)
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 6),
                              // Short form ("My Team" → "Team") and shrink-to-
                              // fit so the label never clips on small phones.
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  tab.label.startsWith('My ')
                                      ? tab.label.substring(3)
                                      : tab.label,
                                  maxLines: 1,
                                  softWrap: false,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: brand,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (tab.badge > 0 && !showLabel)
                    Positioned(
                      top: 5,
                      left: c.maxWidth / 2 + 4,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5484D),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          tab.badge > 99 ? '99+' : '${tab.badge}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One quick action shown on the arc.
class _QuickAction {
  const _QuickAction(this.label, this.icon, this.color, this.run);
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback run;
}

/// Full-screen quick-actions arc (the HTML design's `.orb`): a violet glow
/// scrim, a title, a thin arc and up to five white action bubbles that fly
/// out of the orb. The orb itself (now white with an ×) closes it.
Future<void> _showQuickActions(BuildContext context, List<_QuickAction> actions) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close quick actions',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, _, __) => _QuickActionsOverlay(actions: actions),
    transitionBuilder: (ctx, a, _, child) => FadeTransition(opacity: a, child: child),
  );
}

class _QuickActionsOverlay extends StatefulWidget {
  const _QuickActionsOverlay({required this.actions});
  final List<_QuickAction> actions;

  @override
  State<_QuickActionsOverlay> createState() => _QuickActionsOverlayState();
}

class _QuickActionsOverlayState extends State<_QuickActionsOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = mq.size.width;
    final brand = AppColors.primary;
    // Same spot as the tab-bar orb: bar bottom margin 10 + safe, bar 68,
    // orb centre 7px below the bar top.
    final fabFromBottom = 10 + mq.padding.bottom + _FloatingTabBar.barHeight - 7;
    final fab = Offset(w / 2, mq.size.height - fabFromBottom);
    final r = math.min(140.0, w / 2 - 52);
    final n = widget.actions.length;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              // Blurred, deep violet scrim with a brand glow around the orb.
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0, (fab.dy / mq.size.height) * 2 - 1),
                        radius: 1.1,
                        colors: [
                          Color.lerp(brand, const Color(0xFF140F35), 0.25)!
                              .withOpacity(0.9),
                          const Color(0xEB140F35),
                        ],
                        stops: const [0, 0.62],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: fab.dy - r - 118,
            child: FadeTransition(
              opacity: CurvedAnimation(parent: _c, curve: const Interval(0.1, 0.5)),
              child: const Column(
                children: [
                  Text(
                    'Quick actions',
                    style: TextStyle(
                      fontSize: 22,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Pick one, or tap × to close',
                    style: TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: fab.dx - r,
            top: fab.dy - r,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, __) => CustomPaint(
                  size: Size(r * 2, r * 2),
                  painter: _ArcPainter(
                    Curves.easeInOutCubic.transform(
                        const Interval(0, 0.6).transform(_c.value)),
                  ),
                ),
              ),
            ),
          ),
          for (var i = 0; i < n; i++)
            _bubble(i, n, fab, r),
          Positioned(
            left: fab.dx - 40,
            top: fab.dy - 40,
            child: _QuickOrb(open: true, onTap: () => Navigator.of(context).pop()),
          ),
        ],
      ),
    );
  }

  Widget _bubble(int i, int n, Offset fab, double r) {
    final a = widget.actions[i];
    // Spread over 192°–348° (left to right across the top), like the design.
    final deg = n == 1 ? 270.0 : 192 + i * (156 / (n - 1));
    final rad = deg * math.pi / 180;
    final target = fab + Offset(math.cos(rad) * r, math.sin(rad) * r);
    final start = 0.06 * i;
    final t = CurvedAnimation(
      parent: _c,
      curve: Interval(start, math.min(1, start + 0.62), curve: Curves.easeOutBack),
    );
    return AnimatedBuilder(
      animation: t,
      builder: (context, child) {
        final p = Offset.lerp(fab, target, t.value)!;
        return Positioned(
          left: p.dx - 44,
          top: p.dy - 29,
          child: Opacity(
            opacity: t.value.clamp(0.0, 1.0),
            child: Transform.scale(scale: 0.4 + 0.6 * t.value.clamp(0.0, 1.2), child: child),
          ),
        );
      },
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).pop();
          a.run();
        },
        child: SizedBox(
          width: 88,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    const BoxShadow(
                      color: Color(0x80000000),
                      blurRadius: 24,
                      spreadRadius: -10,
                      offset: Offset(0, 12),
                    ),
                    BoxShadow(color: Colors.white.withOpacity(0.12), spreadRadius: 5),
                  ],
                ),
                foregroundDecoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.4, -0.6),
                    radius: 0.8,
                    colors: [Colors.white.withOpacity(0), a.color.withOpacity(0.06)],
                  ),
                ),
                child: Icon(a.icon, size: 24, color: a.color),
              ),
              const SizedBox(height: 7),
              Text(
                a.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final rect = Offset.zero & size;
    const start = 192 * math.pi / 180;
    const sweep = 156 * math.pi / 180;
    canvas.drawArc(
      rect,
      start,
      sweep * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withOpacity(0.35),
    );
  }

  @override
  bool shouldRepaint(covariant _ArcPainter old) => old.progress != progress;
}

class _Tab {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;

  /// Red count on the tab (0 hides it).
  final int badge;
  const _Tab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.path,
    this.badge = 0,
  });
}
