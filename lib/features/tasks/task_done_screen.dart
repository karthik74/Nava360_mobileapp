import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';

/// Confirmation screen shown after a task form is successfully submitted.
///
/// Replaces the detail screen via `Navigator.pushReplacement` so back goes to
/// the task list rather than the now-stale fill screen.
class TaskDoneScreen extends StatelessWidget {
  const TaskDoneScreen({
    super.key,
    required this.taskTitle,
    this.message,
  });

  final String taskTitle;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.deep,
        body: ProDeepSurface(
          padding: EdgeInsets.zero,
          child: SizedBox.expand(
            child: Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Row(
                      children: [
                        ProHeroIconButton(
                          icon: Icons.close_rounded,
                          tooltip: 'Close',
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        const Expanded(
                          child: Text(
                            'Task complete',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 40),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _DoneMark(),
                          const SizedBox(height: 26),
                          const Text(
                            'Submitted successfully',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 26,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.7,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            taskTitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.4,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // What happens next — white sheet.
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
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
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (message != null) ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ProIconWell(
                                  icon: Icons.task_alt_rounded,
                                  color: AppColors.primary,
                                  size: 38,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      message!,
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        height: 1.45,
                                        color: AppColors.inkSoft,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                          ],
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Back to tasks'),
                          ),
                        ],
                      ),
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

/// Lime check disc with a soft halo.
class _DoneMark extends StatelessWidget {
  const _DoneMark();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutBack,
      builder: (_, t, child) => Transform.scale(scale: t, child: child),
      child: Container(
        width: 132,
        height: 132,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.live.withValues(alpha: 0.12),
          border: Border.all(color: AppColors.live.withValues(alpha: 0.25)),
        ),
        alignment: Alignment.center,
        child: Container(
          width: 92,
          height: 92,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.live,
          ),
          child: Icon(Icons.check_rounded, size: 52, color: AppColors.deep),
        ),
      ),
    );
  }
}
