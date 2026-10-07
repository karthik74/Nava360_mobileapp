import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/branding.dart';
import '../../core/navigation/mobile_menu_config.dart';
import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../attendance/sign_out_guard.dart';
import '../auth/auth_controller.dart';

// ── Menu presentation helpers ────────────────────────────────────────────────
//
// Pure presentation: a one-line description and a section for each menu key.
// The items themselves (which ones show, their order, routes, flags and
// permissions) still come only from `menuFor(...)`.

const Map<String, String> _kMenuSubtitles = {
  'hrms.profile': 'Personal details & documents',
  'hrms.attendance': 'Daily punches & cycle calendar',
  'hrms.leaves': 'Balances, requests & approvals',
  'hrms.tasks': 'Assigned work & due dates',
  'hrms.nearbyCustomers': 'Customers around you',
  'hrms.ptpFollowups': 'Promise-to-pay follow-ups',
  'hrms.interviews': 'Interviews you are part of',
  'hrms.requisitions': 'Open positions & hiring',
  'hrms.helpdesk': 'Raise & track tickets',
  'hrms.travelClaims': 'Claim travel expenses',
  'hrms.travelPlans': 'Plan upcoming trips',
  'hrms.purchaseOrders': 'Raise & track purchase orders',
  'hrms.rentManagement': 'Branch rent & utilities',
  'hrms.mailRecord': 'Inward & outward mail',
  'hrms.letterhead': 'Company letter templates',
  'hrms.itAssets': 'IT asset register',
  'hrms.announcements': 'Company news & notices',
  'hrms.policies': 'HR policies & handbooks',
  'hrms.meetings': 'Upcoming meetings',
  'hrms.trainings': 'Courses & tests',
  'hrms.assets': 'Devices issued to you',
  'hrms.resignation': 'Submit or track your resignation',
  'hrms.performance': 'Scores & reviews',
  'hrms.goals': 'Targets for this cycle',
  'hrms.targetApprovals': 'Review your team\'s targets',
  'hrms.audit': 'Branch audits & findings',
  'hrms.taskReviews': 'Review completed tasks',
  'hrms.npOnboarding': 'Candidate onboarding',
  'pay.payslips': 'Monthly salary slips',
  'pay.salary': 'Earnings & deductions',
  'pay.taxdocs': 'Tax documents for the year',
  'pay.taxdecl': 'Investment declarations',
  'pay.pfesi': 'Provident fund & ESI',
  'more.notifications': 'Alerts & reminders',
  'more.password': 'Update your sign-in password',
  'more.support': 'Get help from the team',
  'more.helpdeskKb': 'Answers to common questions',
};

class _MenuSection {
  const _MenuSection(this.label, this.color);
  final String label;
  final Color color;
}

const _kSectionMe = 0;
const _kSectionField = 1;
const _kSectionRequests = 2;
const _kSectionReviews = 3;
const _kSectionHiring = 4;
const _kSectionOffice = 5;
const _kSectionCompany = 6;
const _kSectionPay = 7;
const _kSectionSettings = 8;
const _kSectionOther = 9;

_MenuSection _sectionInfo(int s) {
  switch (s) {
    case _kSectionMe:
      return _MenuSection('Me', AppColors.primary);
    case _kSectionField:
      return const _MenuSection('Field work', AppColors.success);
    case _kSectionRequests:
      return const _MenuSection('Requests & travel', AppColors.info);
    case _kSectionReviews:
      return const _MenuSection('Reviews & approvals', AppColors.warning);
    case _kSectionHiring:
      return const _MenuSection('Hiring', AppColors.pink);
    case _kSectionOffice:
      return const _MenuSection('Office tools', AppColors.inkSoft);
    case _kSectionCompany:
      return _MenuSection('Company', AppColors.primary);
    case _kSectionPay:
      return const _MenuSection('Pay', AppColors.success);
    case _kSectionSettings:
      return _MenuSection('Settings & support', AppColors.primary);
    default:
      return _MenuSection('More', AppColors.primary);
  }
}

const Map<String, int> _kMenuSectionOf = {
  'hrms.profile': _kSectionMe,
  'hrms.attendance': _kSectionMe,
  'hrms.leaves': _kSectionMe,
  'hrms.tasks': _kSectionMe,
  'hrms.performance': _kSectionMe,
  'hrms.goals': _kSectionMe,
  'hrms.meetings': _kSectionMe,
  'hrms.trainings': _kSectionMe,
  'hrms.assets': _kSectionMe,
  'hrms.resignation': _kSectionMe,
  'hrms.nearbyCustomers': _kSectionField,
  'hrms.ptpFollowups': _kSectionField,
  'hrms.ftodCollections': _kSectionField,
  'hrms.travelClaims': _kSectionRequests,
  'hrms.travelPlans': _kSectionRequests,
  'hrms.helpdesk': _kSectionRequests,
  'hrms.targetApprovals': _kSectionReviews,
  'hrms.taskReviews': _kSectionReviews,
  'hrms.audit': _kSectionReviews,
  'hrms.interviews': _kSectionHiring,
  'hrms.requisitions': _kSectionHiring,
  'hrms.npOnboarding': _kSectionHiring,
  'hrms.purchaseOrders': _kSectionOffice,
  'hrms.rentManagement': _kSectionOffice,
  'hrms.mailRecord': _kSectionOffice,
  'hrms.letterhead': _kSectionOffice,
  'hrms.itAssets': _kSectionOffice,
  'hrms.announcements': _kSectionCompany,
  'hrms.policies': _kSectionCompany,
};

int _sectionOf(MobileMenuItem item) {
  final s = _kMenuSectionOf[item.key];
  if (s != null) return s;
  if (item.key.startsWith('pay.')) return _kSectionPay;
  if (item.key.startsWith('more.')) return _kSectionSettings;
  return _kSectionOther;
}

/// Groups [items] into sections (stable: items keep their configured order
/// inside a section).
List<MapEntry<_MenuSection, List<MobileMenuItem>>> _groupItems(
    List<MobileMenuItem> items) {
  final buckets = <int, List<MobileMenuItem>>{};
  for (final it in items) {
    buckets.putIfAbsent(_sectionOf(it), () => []).add(it);
  }
  final keys = buckets.keys.toList()..sort();
  return [for (final k in keys) MapEntry(_sectionInfo(k), buckets[k]!)];
}

/// One menu row: tinted icon well, label, one-line description, chevron.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item, required this.color});
  final MobileMenuItem item;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ProListRow(
      leading: ProIconWell(icon: item.icon, color: color),
      title: item.label,
      subtitle: _kMenuSubtitles[item.key],
      onTap: () => context.push(item.route),
    );
  }
}

/// Section label + 2-column grid of "lesson card" tiles (soft theme).
class _MenuGrid extends StatelessWidget {
  const _MenuGrid({required this.label, required this.items, required this.color});
  final String label;
  final List<MobileMenuItem> items;
  final Color Function(MobileMenuItem) color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProSectionHeader(title: label, small: true),
        const SizedBox(height: 10),
        GridView.count(
          padding: EdgeInsets.zero,
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.16,
          children: [
            for (final it in items)
              ProMenuTile(
                icon: it.icon,
                color: color(it),
                title: it.label,
                subtitle: _kMenuSubtitles[it.key],
                onTap: () => context.push(it.route),
              ),
          ],
        ),
      ],
    );
  }
}

/// Section label + grouped list.
class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.label, required this.children});
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProSectionHeader(title: label, small: true),
        const SizedBox(height: 8),
        ProListGroup(children: children),
      ],
    );
  }
}

/// Generic, config-driven module screen: grouped menu rows for a
/// [MobileModule]. Items are sourced from `mobile_menu_config.dart` and filtered
/// by the signed-in user's permissions / manager status. Tapping a row PUSHES
/// the route, so the Android back button returns here (not out of the app).
class ModuleGridScreen extends ConsumerStatefulWidget {
  const ModuleGridScreen({
    super.key,
    required this.module,
    required this.title,
    this.subtitle,
  });

  final MobileModule module;
  final String title;
  final String? subtitle;

  @override
  ConsumerState<ModuleGridScreen> createState() => _ModuleGridScreenState();
}

class _ModuleGridScreenState extends ConsumerState<ModuleGridScreen> {
  final _q = TextEditingController();
  String _query = '';

  /// Tiles (grid, default) or rows (list) — like the reference "Your lessons".
  bool _grid = true;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    // Rebuild when the branding refresh lands — menu entries follow its feature flags.
    ref.watch(brandingProvider);
    final items = menuFor(widget.module, user);
    final showSearch = items.length > 6;

    final q = _query.trim().toLowerCase();
    final results = q.isEmpty
        ? items
        : items
            .where((m) =>
                m.label.toLowerCase().contains(q) ||
                (_kMenuSubtitles[m.key]?.toLowerCase().contains(q) ?? false))
            .toList();

    final List<Widget> body;
    if (items.isEmpty) {
      body = [
        ProEmpty(
          icon: Icons.inbox_rounded,
          title: 'Nothing in ${widget.title}',
          message: 'No items are available for your account.',
        ),
      ];
    } else if (q.isNotEmpty) {
      body = [
        if (results.isEmpty)
          ProEmpty(
            icon: Icons.search_off_rounded,
            title: 'No match for “${_query.trim()}”',
            message: 'Try a shorter word.',
          )
        else
          _MenuGroup(
            label: 'Results · ${results.length}',
            children: [
              for (final it in results)
                _MenuRow(item: it, color: _sectionInfo(_sectionOf(it)).color),
            ],
          ),
      ];
    } else {
      body = [
        Row(
          children: [
            Expanded(
              child: Text(
                '${items.length} ${items.length == 1 ? 'menu' : 'menus'}',
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            ProViewToggle(grid: _grid, onChanged: (g) => setState(() => _grid = g)),
          ],
        ),
        for (final g in _groupItems(items))
          if (_grid)
            _MenuGrid(label: g.key.label, items: g.value, color: (_) => g.key.color)
          else
            _MenuGroup(
              label: g.key.label,
              children: [
                for (final it in g.value) _MenuRow(item: it, color: g.key.color),
              ],
            ),
      ];
    }

    return ProPage(
      topInset: MediaQuery.of(context).padding.top,
      clearNav: true,
      gap: 22,
      hero: ProHero(
        title: widget.title,
        subtitle: widget.subtitle,
        overlap: showSearch
            ? ProSearchField(
                raised: true,
                controller: _q,
                hint: 'Search ${widget.title}',
                onChanged: (v) => setState(() => _query = v),
              )
            : null,
      ),
      children: body,
    );
  }
}

/// HRMS self-service module.
class HrmsScreen extends StatelessWidget {
  const HrmsScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const ModuleGridScreen(module: MobileModule.hrms, title: 'HRMS', subtitle: 'Your workplace, attendance, leave & more');
}

/// Payroll self-service module (payslips, salary, tax — no admin/processing).
class PayrollScreen extends StatelessWidget {
  const PayrollScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const ModuleGridScreen(module: MobileModule.payroll, title: 'Payroll', subtitle: 'Payslips, salary & tax');
}

/// "More" — settings/support plus logout.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider);
    ref.watch(brandingProvider);
    final items = menuFor(MobileModule.more, user);
    final fullName = [user?.firstName, user?.lastName]
        .where((s) => s != null && s.trim().isNotEmpty)
        .map((s) => s!.trim())
        .join(' ');
    final displayName = fullName.isNotEmpty ? fullName : (user?.username ?? '');
    final email = user?.email ?? '';

    return ProPage(
      topInset: MediaQuery.of(context).padding.top,
      clearNav: true,
      gap: 22,
      hero: ProHero(
        title: 'More',
        subtitle: 'Settings, support & your account',
        children: [
          if (displayName.isNotEmpty)
            ProHeroIdentity(
              name: displayName,
              role: email.isEmpty ? null : email,
              initials: ProAvatar.initialsOf(displayName),
            ),
        ],
      ),
      children: [
        if (items.isNotEmpty)
          _MenuGroup(
            label: 'Settings & support',
            children: [
              for (final item in items)
                _MenuRow(item: item, color: AppColors.primary),
            ],
          ),
        _LogoutButton(onTap: () => _confirmLogout(context, ref)),
      ],
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    // An open attendance day has to be closed before the session can end.
    if (!await ensureCheckedOutBeforeSignOut(context, ref)) return;
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Logout')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

/// Full-width destructive "Logout" row in a hairline card.
class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.power_settings_new_rounded,
                  size: 19, color: AppColors.danger),
              SizedBox(width: 8),
              Text(
                'Logout',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.danger,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
