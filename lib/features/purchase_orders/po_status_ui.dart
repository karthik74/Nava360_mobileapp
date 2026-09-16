import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Indian-rupee money formatting used across the Purchase Order screens
/// (mirrors `AdminPurchaseOrdersPage.tsx`'s `money()` helper).
String poMoney(double? n) {
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

/// (color, label) tone for a fixed GST-slab percentage
/// ([PoConstants.gstOptions] — 0/5/18%).
StatusTone gstTone(double gstPercent) {
  if (gstPercent <= 0) return const StatusTone(AppColors.muted, '0% GST');
  if (gstPercent <= 5) {
    return StatusTone(AppColors.info, '${gstPercent.toStringAsFixed(0)}% GST');
  }
  return StatusTone(AppColors.warning, '${gstPercent.toStringAsFixed(0)}% GST');
}

/// (color, label) tone for a purchase-order audit-trail action
/// (`AdminPurchaseOrderAuditLog.action`, e.g. `CREATE`/`UPDATE`/`DELETE`).
StatusTone poAuditActionTone(String action) {
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

/// Icon for a purchase order's list-card thumbnail / detail header.
const IconData poDocumentIcon = Icons.receipt_long_rounded;
