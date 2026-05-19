import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Notifications'),
        centerTitle: false,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const AppEmptyState(
            icon: Icons.notifications_none_rounded,
            message: 'No notifications yet.\nWe will let you know when something happens.',
          ),
        ],
      ),
    );
  }
}
