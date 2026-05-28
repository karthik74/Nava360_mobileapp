import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';

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
      label: 'Leaves',
      icon: Icons.event_available_outlined,
      selectedIcon: Icons.event_available_rounded,
      path: '/leaves',
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
    return 'HRMS';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = GoRouterState.of(context).matchedLocation;
    final user = ref.watch(authUserProvider);
    final isManager = user?.hasRole(const {'ADMIN', 'HR'}) ?? false;
    final visibleTabs = isManager ? _bottomTabs : _bottomTabs.take(3).toList();
    final index = _indexFromLocation(loc, visibleTabs);

    return Scaffold(
      key: const ValueKey('home_shell_scaffold'),
      backgroundColor: AppColors.bg,
      drawer: _AppDrawer(currentPath: loc, isManager: isManager),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(72),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
            child: Row(
              children: [
                // Hamburger menu
                Builder(
                  builder: (ctx) => Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Scaffold.of(ctx).openDrawer(),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.hairline),
                          boxShadow: AppShadows.soft,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.menu_rounded,
                          size: 20,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => context.push('/profile'),
                  child: UserAvatar(
                    name: user?.username ?? '',
                    size: 44,
                    radius: 14,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _titleFor(loc),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user?.username ?? '',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                AppIconButton(
                  icon: Icons.notifications_none_rounded,
                  onTap: () => context.push('/notifications'),
                  badge: 0,
                ),
              ],
            ),
          ),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Left Navigation Drawer
// ─────────────────────────────────────────────────────────────────────

class _AppDrawer extends ConsumerWidget {
  const _AppDrawer({required this.currentPath, required this.isManager});
  final String currentPath;
  final bool isManager;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider);
    final mq = MediaQuery.of(context);

    return Drawer(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // ── Header with gradient ──
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              24,
              mq.padding.top + 28,
              24,
              24,
            ),
            decoration: const BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.only(
                bottomRight: Radius.circular(32),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Close button
                Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // User avatar
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.30),
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    (user?.username.isNotEmpty ?? false)
                        ? user!.username[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  user?.username ?? 'User',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user?.email ?? '',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.80),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                // Role pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.25),
                    ),
                  ),
                  child: Text(
                    user?.role ?? 'EMPLOYEE',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Navigation items ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                _DrawerLabel(label: 'MENU'),
                _DrawerNavTile(
                  icon: Icons.home_rounded,
                  label: 'Dashboard',
                  path: '/home',
                  currentPath: currentPath,
                ),
                _DrawerNavTile(
                  icon: Icons.fingerprint_rounded,
                  label: 'Attendance',
                  path: '/attendance',
                  currentPath: currentPath,
                  accentColor: AppColors.accent,
                ),
                _DrawerNavTile(
                  icon: Icons.event_available_rounded,
                  label: 'Leaves',
                  path: '/leaves',
                  currentPath: currentPath,
                  accentColor: AppColors.success,
                ),
                _DrawerNavTile(
                  icon: Icons.task_alt_rounded,
                  label: 'Tasks',
                  path: '/tasks',
                  currentPath: currentPath,
                  accentColor: AppColors.warning,
                ),
                if (isManager)
                  _DrawerNavTile(
                    icon: Icons.groups_2_rounded,
                    label: 'Team',
                    path: '/team',
                    currentPath: currentPath,
                    accentColor: AppColors.pink,
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Divider(height: 1, color: AppColors.hairline),
                ),
                _DrawerLabel(label: 'OTHER'),
                _DrawerNavTile(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                  path: '/profile',
                  currentPath: currentPath,
                  isPush: true,
                ),
                _DrawerNavTile(
                  icon: Icons.notifications_none_rounded,
                  label: 'Notifications',
                  path: '/notifications',
                  currentPath: currentPath,
                  isPush: true,
                ),
              ],
            ),
          ),

          // ── Footer ──
          Container(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: AppColors.hairline.withOpacity(0.7),
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  // Sign out button
                  SizedBox(
                    width: double.infinity,
                    child: Material(
                      color: AppColors.danger.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(context);
                          _showLogoutDialog(context, ref);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 14,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.logout_rounded,
                                size: 18,
                                color: AppColors.danger.withOpacity(0.85),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Sign out',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.danger.withOpacity(0.85),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Nava360 · v1.0',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.muted.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        title: const Text(
          'Sign out?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: const Text(
          'You will need to sign in again to access your workspace.',
          style: TextStyle(
            color: AppColors.inkSoft,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authControllerProvider.notifier).logout();
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Drawer section label
// ─────────────────────────────────────────────────────────────────────

class _DrawerLabel extends StatelessWidget {
  const _DrawerLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: AppColors.muted,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Drawer nav tile
// ─────────────────────────────────────────────────────────────────────

class _DrawerNavTile extends StatelessWidget {
  const _DrawerNavTile({
    required this.icon,
    required this.label,
    required this.path,
    required this.currentPath,
    this.accentColor,
    this.isPush = false,
  });

  final IconData icon;
  final String label;
  final String path;
  final String currentPath;
  final Color? accentColor;
  final bool isPush;

  bool get _selected => currentPath.startsWith(path);

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? AppColors.primary;
    final isActive = _selected;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isActive ? color.withOpacity(0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.md),
          onTap: () {
            Navigator.pop(context); // close drawer
            if (isPush) {
              context.push(path);
            } else {
              context.go(path);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isActive
                        ? color.withOpacity(0.15)
                        : AppColors.bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    size: 20,
                    color: isActive ? color : AppColors.muted,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                      color: isActive ? color : AppColors.inkSoft,
                    ),
                  ),
                ),
                if (isActive)
                  Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: selected ? 1.1 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: Icon(
                selected ? tab.selectedIcon : tab.icon,
                size: 22,
                color: selected ? AppColors.primary : AppColors.muted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.primary : AppColors.muted,
              ),
            ),
          ],
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
