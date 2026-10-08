import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/branding.dart';
import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../attendance/sign_out_guard.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';
import '../auth/biometric/biometric_controller.dart';
import '../home/home_shell.dart' show employeeProfileProvider;
import '../notifications/push_service.dart';
import 'profile_repository.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider);
    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Full employee record from /api/employees/{id}. Null while it loads or
    // when the account isn't linked to an employee — fields fall back to '—'.
    final empId = user.employeeId;
    final profile = empId == null
        ? null
        : ref.watch(employeeProfileProvider(empId)).valueOrNull;

    String? field(String key) {
      final v = profile?[key];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    String fmtDate(String? iso) {
      if (iso == null) return '—';
      final d = DateTime.tryParse(iso);
      return d == null ? iso : DateFormat('d MMM yyyy').format(d);
    }

    final fullName = [field('firstName'), field('lastName')]
        .where((e) => e != null)
        .join(' ')
        .trim();
    final displayName = fullName.isNotEmpty ? fullName : user.displayName;
    final employeeCode = field('employeeCode') ??
        (empId != null
            ? 'EMP-${empId.toString().padLeft(4, '0')}'
            : 'Not linked');

    final pushOn = ref.watch(notificationsEnabledProvider);
    final bio = ref.watch(biometricControllerProvider);
    final roleLine = [field('designation'), field('department')]
        .whereType<String>()
        .join(' · ');
    final branch = field('branchLabel');
    final company = Branding.current.companyShortName;

    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
      body: ProPage(
        hero: ProHero(
          overlap: ProKpiStrip(
            cells: [
              ProKpi(
                value: _tenure(field('joiningDate')),
                label: company.isNotEmpty ? 'With $company' : 'Tenure',
              ),
              ProKpi(
                value: bio.enabled ? 'On' : 'Off',
                label: 'Biometric login',
                valueColor: bio.enabled ? AppColors.success : AppColors.muted,
              ),
              ProKpi(
                value: pushOn ? 'On' : 'Off',
                label: 'Push alerts',
                valueColor: pushOn ? AppColors.success : AppColors.muted,
              ),
            ],
          ),
          children: [
            _ProfileIdentity(
              user: user,
              name: displayName,
              role: roleLine.isNotEmpty ? roleLine : _roleLabel(user.role),
              tags: [
                ProHeroTag(employeeCode),
                ProHeroTag(_roleLabel(user.role), tone: ProTagTone.ok),
                if (branch != null) ProHeroTag(branch),
              ],
            ),
            ProHeroActions(
              actions: [
                ProAction(
                  icon: Icons.badge_outlined,
                  label: 'Card',
                  primary: true,
                  onTap: () => context.push('/business-card'),
                ),
                ProAction(
                  icon: Icons.folder_shared_outlined,
                  label: 'Documents',
                  onTap: () => context.push('/profile/documents'),
                ),
                ProAction(
                  icon: Icons.lock_outline_rounded,
                  label: 'Password',
                  onTap: () => context.push('/change-password'),
                ),
                ProAction(
                  icon: Icons.help_outline_rounded,
                  label: 'Help',
                  onTap: () => context.push('/help-support'),
                ),
              ],
            ),
          ],
        ),
        children: [
          // Personal details
          GlassCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProSectionHeader(title: 'Personal details'),
                const SizedBox(height: 4),
                ProKeyValue(
                  rows: [
                    MapEntry('Full name', displayName),
                    MapEntry('Employee ID', employeeCode),
                    MapEntry(Branding.current.term('department'),
                        field('department') ?? '—'),
                    MapEntry(Branding.current.term('designation'),
                        field('designation') ?? '—'),
                    MapEntry('Joining date', fmtDate(field('joiningDate'))),
                    MapEntry('Email', field('email') ?? user.email),
                    MapEntry('Phone', field('phone') ?? '—'),
                    MapEntry('Manager', field('reportingManagerName') ?? '—'),
                    MapEntry('Working branch', branch ?? '—'),
                  ],
                ),
              ],
            ),
          ),

          // Documents
          const ProSectionHeader(title: 'Documents', small: true),
          ProListGroup(
            children: [
              ProListRow(
                leading: ProIconWell(
                  icon: Icons.folder_shared_outlined,
                  color: AppColors.primary,
                ),
                title: 'My documents',
                onTap: () => context.push('/profile/documents'),
              ),
              ProListRow(
                leading: const ProIconWell(
                  icon: Icons.badge_outlined,
                  color: AppColors.accent,
                ),
                title: 'My business card',
                onTap: () => context.push('/business-card'),
              ),
            ],
          ),

          // Settings
          const ProSectionHeader(title: 'Settings', small: true),
          ProListGroup(
            children: [
              _SwitchRow(
                icon: Icons.notifications_active_outlined,
                color: AppColors.warning,
                label: 'Push notifications',
                value: pushOn,
                onChanged: (v) => ref
                    .read(notificationsEnabledProvider.notifier)
                    .setEnabled(v),
              ),
              ProListRow(
                leading: const ProIconWell(
                  icon: Icons.notifications_outlined,
                  color: AppColors.info,
                ),
                title: 'Notification history',
                onTap: () => context.push('/notifications'),
              ),
              ProListRow(
                leading: ProIconWell(
                  icon: Icons.lock_outline_rounded,
                  color: AppColors.primary,
                ),
                title: 'Change password',
                onTap: () => context.push('/change-password'),
              ),
              ProListRow(
                leading: const ProIconWell(
                  icon: Icons.help_outline_rounded,
                  color: AppColors.success,
                ),
                title: 'Help & support',
                onTap: () => context.push('/help-support'),
              ),
            ],
          ),

          // Security
          const ProSectionHeader(title: 'Security', small: true),
          ProListGroup(
            children: [
              _SwitchRow(
                icon: Icons.fingerprint_rounded,
                color: AppColors.primary,
                label: 'Biometric login',
                value: bio.enabled,
                onChanged: bio.busy
                    ? (_) {}
                    : (v) => _toggleBiometric(context, ref, v),
              ),
              ProListRow(
                leading: const ProIconWell(icon: Icons.devices_other_rounded),
                title: 'Registered devices',
                onTap: () => context.push('/security/devices'),
              ),
            ],
          ),

          // Sign out
          const SizedBox(height: 4),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: () => _handleLogout(context, ref),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.dangerTint,
                foregroundColor: AppColors.danger,
              ),
              icon: const Icon(Icons.logout_rounded, size: 19),
              label: const Text('Sign out'),
            ),
          ),
          Center(
            child: Text(
              '${Branding.current.productName} Mobile v1.0',
              style: const TextStyle(
                color: AppColors.faint,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "EMPLOYEE" → "Employee", "BRANCH_MANAGER" → "Branch manager".
String _roleLabel(String role) {
  final s = role.replaceAll('_', ' ').trim().toLowerCase();
  if (s.isEmpty) return role;
  return s[0].toUpperCase() + s.substring(1);
}

/// Time since the joining date, e.g. "7y 3m" (— when unknown).
String _tenure(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso);
  if (d == null) return '—';
  final now = DateTime.now();
  var months = (now.year - d.year) * 12 + now.month - d.month;
  if (now.day < d.day) months--;
  if (months < 0) return '—';
  final y = months ~/ 12;
  final m = months % 12;
  if (y == 0) return '${m}m';
  return m == 0 ? '${y}y' : '${y}y ${m}m';
}

/// Turns biometric login on (verify + enroll) or off (confirm + disable).
Future<void> _toggleBiometric(
    BuildContext context, WidgetRef ref, bool enable) async {
  final ctrl = ref.read(biometricControllerProvider.notifier);
  if (enable) {
    final err = await ctrl.enable();
    if (context.mounted) {
      final label = ref.read(biometricControllerProvider).label;
      _snack(context, err ?? '$label login enabled', error: err != null);
    }
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      title: const Text('Disable biometric login?'),
      content: const Text(
        'This device will require Employee ID and Password for the next login.',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel')),
        FilledButton(
          style: _destructive,
          onPressed: () => Navigator.pop(dctx, true),
          child: const Text('Disable'),
        ),
      ],
    ),
  );
  if (ok == true) {
    await ctrl.disable();
    if (context.mounted) _snack(context, 'Biometric login disabled');
  }
}

/// Sign out. When biometric is enabled, offer to keep it or disable it (spec §6).
Future<void> _handleLogout(BuildContext context, WidgetRef ref) async {
  // Guarded before either dialog: being asked to keep biometric login on, only
  // to be refused afterwards, would read as the app losing track of itself.
  if (!await ensureCheckedOutBeforeSignOut(context, ref)) return;
  if (!context.mounted) return;
  final biometricEnabled = ref.read(biometricControllerProvider).enabled;

  if (!biometricEnabled) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will need to sign in again to access your workspace.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: _destructive,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(authControllerProvider.notifier).logout();
    return;
  }

  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sign out'),
      content: const Text(
        'Do you want to keep biometric login enabled for the next sign-in?',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'disable'),
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          child: const Text('Logout & disable'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, 'keep'),
          child: const Text('Logout only'),
        ),
      ],
    ),
  );
  if (choice == null) return;
  if (choice == 'disable') {
    await ref.read(biometricControllerProvider.notifier).disable();
  }
  await ref.read(authControllerProvider.notifier).logout();
}

final ButtonStyle _destructive = FilledButton.styleFrom(
  backgroundColor: AppColors.dangerTint,
  foregroundColor: AppColors.danger,
);

void _snack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? AppColors.danger : null,
  ));
}

/// Hero identity: photo / initials squircle (with the change-photo button),
/// name, role line and tags. Mirrors [ProHeroIdentity] but supports a photo.
class _ProfileIdentity extends StatelessWidget {
  const _ProfileIdentity({
    required this.user,
    required this.name,
    required this.role,
    required this.tags,
  });

  final AuthUser user;
  final String name;
  final String role;
  final List<ProHeroTag> tags;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ProfileAvatar(user: user, name: name),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  height: 1.22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.55,
                  color: Colors.white,
                ),
              ),
              if (role.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    role,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: Colors.white70,
                    ),
                  ),
                ),
              if (tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Wrap(spacing: 6, runSpacing: 6, children: tags),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileAvatar extends ConsumerStatefulWidget {
  const _ProfileAvatar({required this.user, required this.name});
  final AuthUser user;
  final String name;

  @override
  ConsumerState<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends ConsumerState<_ProfileAvatar> {
  bool _busy = false;

  Future<void> _pickAndUpload(ImageSource source) async {
    final empId = widget.user.employeeId;
    if (empId == null) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;
      setState(() => _busy = true);
      await ref
          .read(profileRepositoryProvider)
          .uploadPhoto(picked.path, filename: picked.name);
      ref.invalidate(employeeProfileProvider(empId));
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Profile photo updated.')),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showPicker() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFC6D3D6),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Profile photo',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.35,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ProListGroup(
                  children: [
                    ProListRow(
                      leading: ProIconWell(
                        icon: Icons.photo_camera_outlined,
                        color: AppColors.primary,
                      ),
                      title: 'Take photo',
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndUpload(ImageSource.camera);
                      },
                    ),
                    ProListRow(
                      leading: ProIconWell(
                        icon: Icons.photo_library_outlined,
                        color: AppColors.primary,
                      ),
                      title: 'Choose from gallery',
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndUpload(ImageSource.gallery);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final empId = widget.user.employeeId;
    final profile = empId == null
        ? null
        : ref.watch(employeeProfileProvider(empId)).valueOrNull;
    final imageUrl = absoluteFileUrl(profile?['profileImageUrl'] as String?);
    final initialsSource =
        widget.name.isNotEmpty ? widget.name : widget.user.username;

    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 4,
            top: 4,
            child: Container(
              width: 64,
              height: 64,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: AppColors.deep, spreadRadius: 3),
                  const BoxShadow(color: AppColors.live, spreadRadius: 5),
                ],
              ),
              alignment: Alignment.center,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageUrl == null)
                    Center(
                      child: Text(
                        ProAvatar.initialsOf(initialsSource),
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.4,
                          color: AppColors.deep,
                        ),
                      ),
                    )
                  else
                    Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                        child: Text(
                          ProAvatar.initialsOf(initialsSource),
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                            color: AppColors.deep,
                          ),
                        ),
                      ),
                    ),
                  if (_busy)
                    const ColoredBox(
                      color: Color(0x59000000),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (empId != null)
            Positioned(
              right: -12,
              bottom: -12,
              child: Tooltip(
                message: 'Change profile photo',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _busy ? null : _showPicker,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: AppColors.primary, width: 2),
                        ),
                        child: Icon(Icons.photo_camera_rounded,
                            color: AppColors.primary, size: 14),
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

/// List row with a switch on the right (no chevron).
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color color;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ProListRow(
      dense: true,
      leading: ProIconWell(icon: icon, color: color),
      title: label,
      chevron: false,
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }
}
