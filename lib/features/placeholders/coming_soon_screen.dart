import 'package:flutter/material.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';

/// Reusable "Coming soon" placeholder used by My Meetings / Trainings /
/// Payslips while their backend wiring is in flight. Uses the same Pro chrome
/// (deep app bar + hero, white cards) as the rest of the app so it doesn't
/// feel like a dead end.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({
    super.key,
    required this.title,
    required this.icon,
    this.accent,
    this.description,
  });

  final String title;
  final IconData icon;
  final Color? accent;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final Color accent = this.accent ?? AppColors.primary;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ProPage(
        hero: ProHero(kicker: 'Coming soon', title: title),
        children: [
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
            child: Column(
              children: [
                ProIconWell(icon: icon, color: accent, size: 56),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppText.title,
                ),
                const SizedBox(height: 8),
                ProPill(
                  'Coming soon',
                  color: accent,
                  background: accent.withOpacity(0.12),
                ),
                const SizedBox(height: 14),
                Text(
                  description ??
                      "We're putting the finishing touches on this. "
                          "It'll be available in an upcoming release.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: AppColors.inkSoft,
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
