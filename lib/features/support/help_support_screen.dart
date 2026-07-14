import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/branding.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Help & support screen — contact channels, FAQs and app info. Support
/// contacts come from the runtime company branding (/api/public/branding);
/// tiles with no configured value are hidden.
class HelpSupportScreen extends ConsumerWidget {
  const HelpSupportScreen({super.key});

  Future<void> _launch(BuildContext context, Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open ${uri.scheme}')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No app available to handle this.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(brandingProvider);
    final supportEmail = b.supportEmail;
    final supportPhone = b.supportPhone;
    final website = b.website;
    return Scaffold(
      appBar: AppBar(title: const Text('Help & support')),
      body: GlassBackdrop(
        child: SafeArea(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              const AppPageHeader(
                title: 'Help & support',
                subtitle: 'We are here to help you',
              ),
              const SizedBox(height: 18),
              const AppSectionHeader(title: 'Contact us'),
              const SizedBox(height: 8),
              if (supportEmail.isNotEmpty)
                _ContactTile(
                  icon: Icons.email_outlined,
                  color: AppColors.info,
                  label: 'Email support',
                  value: supportEmail,
                  onTap: () => _launch(
                    context,
                    Uri(
                      scheme: 'mailto',
                      path: supportEmail,
                      query: 'subject=${b.productName} app support',
                    ),
                  ),
                ),
              if (supportPhone.isNotEmpty) ...[
                const SizedBox(height: 8),
                _ContactTile(
                  icon: Icons.call_outlined,
                  color: AppColors.success,
                  label: 'Call us',
                  value: supportPhone,
                  onTap: () => _launch(
                    context,
                    Uri(scheme: 'tel', path: supportPhone),
                  ),
                ),
              ],
              if (website.isNotEmpty) ...[
                const SizedBox(height: 8),
                _ContactTile(
                  icon: Icons.language_outlined,
                  color: AppColors.accent,
                  label: 'Website',
                  value: website.replaceFirst('https://', ''),
                  onTap: () => _launch(context, Uri.parse(website)),
                ),
              ],
              const SizedBox(height: 8),
              _ContactTile(
                icon: Icons.privacy_tip_outlined,
                color: AppColors.primary,
                label: 'Privacy Policy',
                value: 'How we handle your data',
                onTap: () => _launch(context, Uri.parse(b.effectivePrivacyUrl)),
              ),
              const SizedBox(height: 22),
              const AppSectionHeader(title: 'Frequently asked'),
              const SizedBox(height: 8),
              const _FaqCard(),
              const SizedBox(height: 22),
              const AppSectionHeader(title: 'App info'),
              const SizedBox(height: 8),
              const _AppInfoCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
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

class _FaqCard extends StatelessWidget {
  const _FaqCard();

  static const _faqs = [
    (
      'I am getting 401 / logged out errors',
      'This usually means you signed in on another device, which ends your '
          'session here. Sign in again to continue.',
    ),
    (
      'My attendance check-in is not working',
      'Make sure location is allowed "all the time" and your device location '
          'service is on. You can grant this from your phone Settings.',
    ),
    (
      'I am not receiving notifications',
      'Check that notifications are enabled in Profile → Settings, and that the '
          'app has notification permission in your phone Settings.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < _faqs.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, indent: 16, endIndent: 16),
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                childrenPadding:
                    const EdgeInsets.fromLTRB(16, 0, 16, 14),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                iconColor: AppColors.primary,
                collapsedIconColor: AppColors.muted,
                title: Text(
                  _faqs[i].$1,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                children: [
                  Text(
                    _faqs[i].$2,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppColors.inkSoft,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AppInfoCard extends ConsumerWidget {
  const _AppInfoCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productName = ref.watch(brandingProvider).productName;
    return GlassCard(
      child: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snap) {
          final info = snap.data;
          final version = info == null
              ? '—'
              : 'v${info.version} (${info.buildNumber})';
          return Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary.withOpacity(0.22)),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.info_outline_rounded,
                    color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  productName,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Text(
                version,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
