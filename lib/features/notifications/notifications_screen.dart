import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(
          mq.padding.top + AppChrome.appBarHeight,
        ),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: GlassBlur.chrome,
              sigmaY: GlassBlur.chrome,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.55),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withOpacity(0.55),
                  ),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(0),
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
                                  onTap: () =>
                                      Navigator.of(context).maybePop(),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.55),
                                      ),
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
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Notifications',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: GlassBackdrop(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            mq.padding.top + AppChrome.appBarHeight + 12,
            16,
            mq.padding.bottom + 24,
          ),
          children: const [
            AppEmptyState(
              icon: Icons.notifications_none_rounded,
              message:
                  'No notifications yet.\nWe will let you know when something happens.',
            ),
          ],
        ),
      ),
    );
  }
}
