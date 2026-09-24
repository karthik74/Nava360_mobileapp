import 'package:flutter/material.dart';

import 'rent_models.dart';
import 'rent_repository.dart';

/// Mirrors web `needsGstConfirmation`: GST preference unset, or its lock period has expired.
bool rentNeedsGstConfirmation(RentBranch b) {
  if (b.gstApplicable == null) return true;
  if (b.gstLockedUntil == null) return false;
  return b.gstLockedUntil!.isBefore(DateTime.now());
}

/// End of *next* month — the lock the web applies when the preference is confirmed.
DateTime rentNextGstLockDate() {
  final now = DateTime.now();
  return DateTime(now.year, now.month + 2, 0);
}

/// Before submitting a payable row, prompts "Apply GST for this branch?" when the branch's GST
/// preference is unset/expired (web `RentGstPopup`), saves it with a fresh lock, and returns true
/// when the submit may proceed. Returns false if the user cancelled or saving failed.
Future<bool> confirmGstBeforeSubmit(BuildContext context, RentRepository repo, int branchId) async {
  RentBranch? found;
  try {
    final all = await repo.listBranches();
    for (final b in all) {
      if (b.id == branchId) found = b;
    }
  } catch (_) {
    return true; // can't tell - let the server decide.
  }
  if (found == null || !rentNeedsGstConfirmation(found)) return true;
  if (!context.mounted) return false;
  final branch = found;

  bool apply = true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Apply GST for this branch?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${branch.branchName}${(branch.branchCode ?? '').isEmpty ? '' : ' · ${branch.branchCode}'}',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            const Text('If GST is applicable, SGST 9% + CGST 9% = 18% is added on top of the monthly rent.',
                style: TextStyle(fontSize: 12.5)),
            RadioListTile<bool>(
              contentPadding: EdgeInsets.zero,
              value: true,
              groupValue: apply,
              onChanged: (v) => setS(() => apply = true),
              title: const Text('Yes - apply 18% GST'),
              subtitle: const Text('Adds SGST 9% + CGST 9% on each invoice.'),
            ),
            RadioListTile<bool>(
              contentPadding: EdgeInsets.zero,
              value: false,
              groupValue: apply,
              onChanged: (v) => setS(() => apply = false),
              title: const Text('No - no GST'),
              subtitle: const Text('Invoices are issued without GST.'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    ),
  );
  if (ok != true) return false;
  try {
    await repo.saveGstPreference(branch, apply: apply, lockedUntil: rentNextGstLockDate());
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save GST preference: $e')));
    }
    return false;
  }
}
