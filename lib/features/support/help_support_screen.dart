import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/branding.dart';
import '../../core/pro_ui.dart';
import '../../core/theme.dart';

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
      appBar: AppBar(title: const Text('Support')),
      body: ProPage(
        hero: ProHero(
          title: 'Help & support',
          subtitle: 'Support team · ${b.productName}',
          children: const [
            ProHeroIdentity(
              name: 'We are here to help you',
              role: 'Write or call the support team, or check the common '
                  'questions below.',
              icon: Icons.support_agent_rounded,
            ),
          ],
        ),
        children: [
          const ProSectionHeader(title: 'Contact us', small: true),
          ProListGroup(
            children: [
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
              if (supportPhone.isNotEmpty)
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
              if (website.isNotEmpty)
                _ContactTile(
                  icon: Icons.language_outlined,
                  color: AppColors.pink,
                  label: 'Website',
                  value: website.replaceFirst('https://', ''),
                  onTap: () => _launch(context, Uri.parse(website)),
                ),
              _ContactTile(
                icon: Icons.privacy_tip_outlined,
                color: AppColors.primary,
                label: 'Privacy Policy',
                value: 'How we handle your data',
                onTap: () => _launch(context, Uri.parse(b.effectivePrivacyUrl)),
              ),
            ],
          ),
          const ProSectionHeader(title: 'Frequently asked', small: true),
          const _FaqCard(),
          const ProSectionHeader(title: 'App info', small: true),
          const _AppInfoCard(),
        ],
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
    return ProListRow(
      leading: ProIconWell(icon: icon, color: color),
      title: label,
      subtitle: value,
      onTap: onTap,
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
    return ProListGroup(
      children: [
        for (final f in _faqs)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
              childrenPadding: const EdgeInsets.fromLTRB(58, 0, 16, 14),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              iconColor: AppColors.primary,
              collapsedIconColor: AppColors.faint,
              leading: const ProIconWell(icon: Icons.help_outline_rounded),
              title: Text(
                f.$1,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.33,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.15,
                  color: AppColors.ink,
                ),
              ),
              children: [
                Text(
                  f.$2,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AppInfoCard extends ConsumerWidget {
  const _AppInfoCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productName = ref.watch(brandingProvider).productName;
    return ProListGroup(
      children: [
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snap) {
            final info = snap.data;
            final version = info == null
                ? '—'
                : 'v${info.version} (${info.buildNumber})';
            return ProListRow(
              leading: ProIconWell(
                icon: Icons.info_outline_rounded,
                color: AppColors.primary,
              ),
              title: productName,
              subtitle: 'App version',
              pill: ProPill.neutral(version),
            );
          },
        ),
      ],
    );
  }
}
