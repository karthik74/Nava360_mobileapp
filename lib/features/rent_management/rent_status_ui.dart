import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'rent_models.dart';

/// Indian-rupee money formatting used across the Rent Management screens
/// (mirrors `AdminRentPage.tsx`'s `money()` helper and Purchase Orders'
/// `poMoney()`).
String rentMoney(double? n) {
  if (n == null) return '—';
  final s = n.toStringAsFixed(2);
  final parts = s.split('.');
  final whole = parts[0];
  final neg = whole.startsWith('-');
  final digits = neg ? whole.substring(1) : whole;
  final buf = StringBuffer();
  final len = digits.length;
  for (int i = 0; i < len; i++) {
    buf.write(digits[i]);
    final remaining = len - i - 1;
    if (remaining > 0) {
      if (remaining == 3 || (remaining > 3 && (remaining - 3) % 2 == 0)) {
        buf.write(',');
      }
    }
  }
  return '${neg ? '-' : ''}₹$buf.${parts[1]}';
}

/// (color, label) tone for a rent-payable workflow status
/// (`AdminRentPayableStatus` — PENDING → SUBMITTED → APPROVED → PAID, with a
/// HELD side state), mirroring the web's `statusBadge()`.
StatusTone rentPayableStatusTone(String status) {
  switch (status.toUpperCase()) {
    case RentPayableStatus.pending:
      return const StatusTone(AppColors.muted, 'Pending');
    case RentPayableStatus.submitted:
      return const StatusTone(AppColors.info, 'Submitted');
    case RentPayableStatus.approved:
      return const StatusTone(AppColors.warning, 'Approved');
    case RentPayableStatus.paid:
      return const StatusTone(AppColors.success, 'Paid');
    case RentPayableStatus.held:
      return const StatusTone(AppColors.danger, 'Held');
    default:
      return StatusTone(AppColors.muted, status);
  }
}

/// Icon + label for a utility-bill kind (`AdminRentUtilityKind`).
IconData rentUtilityKindIcon(String kind) {
  switch (kind.toUpperCase()) {
    case RentUtilityKind.internet:
      return Icons.wifi_rounded;
    case RentUtilityKind.electricity:
    default:
      return Icons.bolt_rounded;
  }
}

String rentUtilityKindLabel(String kind) {
  switch (kind.toUpperCase()) {
    case RentUtilityKind.internet:
      return 'Internet';
    case RentUtilityKind.electricity:
    default:
      return 'Electricity';
  }
}

/// (color, label) tone for a rent audit-trail action
/// (`AdminRentAuditLog.action`, e.g. `CREATE`/`UPDATE`/`DELETE`).
StatusTone rentAuditActionTone(String action) {
  switch (action.toUpperCase()) {
    case 'CREATE':
    case 'CREATED':
      return const StatusTone(AppColors.success, 'Created');
    case 'UPDATE':
    case 'UPDATED':
      return const StatusTone(AppColors.info, 'Updated');
    case 'DELETE':
    case 'DELETED':
      return const StatusTone(AppColors.danger, 'Deleted');
    default:
      return StatusTone(AppColors.muted, action);
  }
}

/// Icon for a rent branch's list-card thumbnail / detail header.
const IconData rentBranchIcon = Icons.home_work_rounded;
