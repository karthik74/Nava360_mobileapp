import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../auth/auth_controller.dart';
import 'attendance_repository.dart';
import 'location_tracker.dart';

/// Keeps an open attendance day from being ended by signing out.
///
/// Signing out stops location tracking and drops the session, so an employee who
/// leaves while still checked in ends the day with a check-in and no check-out —
/// which reads as an incomplete day and has to be corrected by hand. Checking out
/// is the only way to close it, so sign-out waits for it.
///
/// This is a workflow guard, not a security control: it refuses the button, it
/// does not hold a session open. A token that expires, a session displaced from
/// another device and the 401 path all still sign the user out, exactly as before.

/// Whether the signed-in employee is checked in with no check-out yet.
///
/// Two signals, in order of how much they can be trusted offline:
///
///  1. The location tracker. It starts at check-in, stops at check-out, and is
///     restored after the app is killed, so it answers correctly with no network
///     at all — which matters, because a field employee finishing a day out of
///     coverage is exactly who this guard is for.
///  2. Today's attendance record from the server, for the case where tracking
///     never started (a shift with tracking off, a restored session that has not
///     resumed yet).
///
/// When neither can answer — the request fails, the employee id is unknown — the
/// answer is "not checked in". Being unable to prove somebody is checked in is a
/// poor reason to trap them in the app.
Future<bool> isCheckedInNow(WidgetRef ref) async {
  if (ref.read(locationTrackerProvider).active) return true;

  final employeeId = ref.read(authUserProvider)?.employeeId;
  if (employeeId == null) return false;

  try {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final rows = await ref
        .read(attendanceRepositoryProvider)
        .listForEmployee(employeeId, from: today, to: today);
    for (final r in rows) {
      if (r.date == today && r.checkIn != null && r.checkOut == null) {
        return true;
      }
    }
  } catch (_) {
    // Offline or the call failed — fall through to allowing the sign-out.
  }
  return false;
}

/// Tells the employee why sign-out is refused and offers to take them to the
/// check-out button.
///
/// Takes only a [BuildContext] so it can be shown after the caller's own widget
/// (a drawer, a sheet) has been dismissed and its `ref` is gone.
Future<void> showCheckOutRequiredDialog(BuildContext context) async {
  final goToCheckOut = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
      title: const Text(
        'Check out first',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      content: const Text(
        'You are still checked in for today. Check out before signing out, so '
        'your day is recorded with the right working hours.',
        style: TextStyle(color: AppColors.inkSoft, fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Go to check-out'),
        ),
      ],
    ),
  );
  if (goToCheckOut == true && context.mounted) context.go('/home');
}

/// The whole guard for callers whose `ref` outlives the check.
///
/// Returns true when signing out may go ahead, and false once it has told the
/// employee to check out first.
Future<bool> ensureCheckedOutBeforeSignOut(
  BuildContext context,
  WidgetRef ref,
) async {
  if (!await isCheckedInNow(ref)) return true;
  if (context.mounted) await showCheckOutRequiredDialog(context);
  return false;
}
