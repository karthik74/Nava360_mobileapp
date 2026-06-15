import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';
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
    final mq = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const _BackButton(),
      ),
      body: GlassBackdrop(
        child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                mq.padding.top + kToolbarHeight + 8,
                16,
                mq.padding.bottom + 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppPageHeader(
                    title: 'Profile',
                    subtitle: 'Your account and preferences',
                  ),
                  const SizedBox(height: 18),

                  // Avatar + name
                  Center(
                    child: Column(
                      children: [
                        _ProfileAvatar(user: user),
                        const SizedBox(height: 12),
                        Text(
                          user.username,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                            border: Border.all(
                              color: AppColors.primary.withOpacity(0.25),
                            ),
                          ),
                          child: Text(
                            user.role,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Info cards
                  const AppSectionHeader(title: 'Account info'),
                  const SizedBox(height: 8),
                  _InfoCard(
                    icon: Icons.email_outlined,
                    label: 'Email',
                    value: user.email,
                    color: AppColors.info,
                  ),
                  const SizedBox(height: 8),
                  _InfoCard(
                    icon: Icons.badge_outlined,
                    label: 'Employee ID',
                    value: user.employeeId?.toString() ?? 'Not linked',
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: 8),
                  _InfoCard(
                    icon: Icons.person_outline,
                    label: 'User ID',
                    value: '#${user.userId}',
                    color: AppColors.success,
                  ),
                  const SizedBox(height: 22),

                  // Settings
                  const AppSectionHeader(title: 'Settings'),
                  const SizedBox(height: 8),
                  _SettingSwitchTile(
                    icon: Icons.notifications_active_outlined,
                    label: 'Push notifications',
                    value: ref.watch(notificationsEnabledProvider),
                    onChanged: (v) => ref
                        .read(notificationsEnabledProvider.notifier)
                        .setEnabled(v),
                  ),
                  const SizedBox(height: 8),
                  _SettingTile(
                    icon: Icons.notifications_outlined,
                    label: 'Notification history',
                    onTap: () => context.push('/notifications'),
                  ),
                  const SizedBox(height: 8),
                  _SettingTile(
                    icon: Icons.lock_outline_rounded,
                    label: 'Change password',
                    onTap: () => context.push('/change-password'),
                  ),
                  const SizedBox(height: 8),
                  _SettingTile(
                    icon: Icons.help_outline_rounded,
                    label: 'Help & support',
                    onTap: () => context.push('/help-support'),
                  ),
                  const SizedBox(height: 22),

                  // Logout
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
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
                                  ref
                                      .read(authControllerProvider.notifier)
                                      .logout();
                                },
                                child: const Text('Sign out'),
                              ),
                            ],
                          ),
                        );
                      },
                      icon: const Icon(Icons.logout_rounded,
                          color: AppColors.danger),
                      label: const Text(
                        'Sign out',
                        style: TextStyle(color: AppColors.danger),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.danger),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.md),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'Nava360 Mobile v1.0',
                      style: TextStyle(
                        color: AppColors.muted.withOpacity(0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 44,
        height: 44,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Material(
              color: Colors.white.withOpacity(0.55),
              child: InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.55)),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    size: 20,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(12),
      shadow: AppShadows.soft,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.22)),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends ConsumerStatefulWidget {
  const _ProfileAvatar({required this.user});
  final AuthUser user;

  @override
  ConsumerState<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends ConsumerState<_ProfileAvatar> {
  bool _busy = false;

  String get _initial =>
      widget.user.username.isNotEmpty ? widget.user.username[0].toUpperCase() : '?';

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
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppColors.primary),
              title: const Text('Take photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUpload(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.primary),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUpload(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
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

    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              gradient: imageUrl == null ? AppColors.heroGradient : null,
              color: imageUrl == null ? null : AppColors.surfaceAlt,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.32),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
              border: Border.all(
                color: Colors.white.withOpacity(0.55),
                width: 1.5,
              ),
              image: imageUrl == null
                  ? null
                  : DecorationImage(
                      image: NetworkImage(imageUrl),
                      fit: BoxFit.cover,
                    ),
            ),
            alignment: Alignment.center,
            child: imageUrl == null
                ? Text(
                    _initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : null,
          ),
          if (_busy)
            Positioned(
              width: 76,
              height: 76,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
              ),
            ),
          if (empId != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onTap: _busy ? null : _showPicker,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      color: Colors.white, size: 15),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingSwitchTile extends StatelessWidget {
  const _SettingSwitchTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      shadow: AppShadows.soft,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.55),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.6)),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: AppColors.inkSoft, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: GlassCard(
          padding: const EdgeInsets.all(12),
          shadow: AppShadows.soft,
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(0.6)),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: AppColors.inkSoft, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
