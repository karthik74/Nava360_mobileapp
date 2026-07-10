import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'travel_models.dart';

/// (color, label) tone for a `TravelClaimStatus`. Mirrors the web claim-status
/// chips so the two front-ends read the same.
StatusTone claimStatusTone(String status) {
  switch (status) {
    case 'DRAFT':
      return const StatusTone(AppColors.muted, 'Draft');
    case 'SUBMITTED':
      return const StatusTone(AppColors.warning, 'Submitted');
    case 'LEVEL_1_APPROVED':
      return const StatusTone(AppColors.info, 'L1 Approved');
    case 'LEVEL_2_APPROVED':
      return const StatusTone(AppColors.info, 'L2 Approved');
    case 'LEVEL_3_APPROVED':
      return const StatusTone(AppColors.info, 'L3 Approved');
    case 'APPROVED':
      return const StatusTone(AppColors.success, 'Approved');
    case 'REJECTED':
      return const StatusTone(AppColors.danger, 'Rejected');
    case 'SENT_BACK':
      return const StatusTone(AppColors.pink, 'Sent back');
    case 'SETTLED':
      return StatusTone(AppColors.primary, 'Settled');
    default:
      return StatusTone(AppColors.muted, TravelEnums.label(status));
  }
}

/// (color, label) tone for a `TravelPlanStatus`.
StatusTone planStatusTone(String status) {
  switch (status) {
    case 'ACTIVE':
      return const StatusTone(AppColors.success, 'Active');
    case 'COMPLETED':
      return const StatusTone(AppColors.info, 'Completed');
    case 'CANCELLED':
      return const StatusTone(AppColors.muted, 'Cancelled');
    default:
      return StatusTone(AppColors.muted, TravelEnums.label(status));
  }
}

/// A claim header is editable by its owner only while DRAFT or SENT_BACK.
bool claimIsEditable(String status) => status == 'DRAFT' || status == 'SENT_BACK';

/// Icon for a `TravelExpenseCategory`.
IconData expenseCategoryIcon(String category) {
  switch (category) {
    case 'TRAVEL_FARE':
      return Icons.flight_takeoff_rounded;
    case 'ACCOMMODATION':
      return Icons.hotel_rounded;
    case 'MEALS':
      return Icons.restaurant_rounded;
    case 'LOCAL_CONVEYANCE':
      return Icons.local_taxi_rounded;
    case 'FUEL':
      return Icons.local_gas_station_rounded;
    case 'COMMUNICATION':
      return Icons.call_rounded;
    default:
      return Icons.receipt_long_rounded;
  }
}

/// Icon for a `TravelMode`.
IconData travelModeIcon(String? mode) {
  switch (mode) {
    case 'BIKE':
      return Icons.two_wheeler_rounded;
    case 'BUS':
      return Icons.directions_bus_rounded;
    case 'TRAIN':
      return Icons.train_rounded;
    case 'TAXI':
      return Icons.local_taxi_rounded;
    case 'OWN_CAR':
      return Icons.directions_car_rounded;
    case 'OFFICE_CAR':
      return Icons.directions_car_filled_rounded;
    default:
      return Icons.alt_route_rounded;
  }
}

/// Indian-rupee money formatting used across the travel screens.
String money(double? v) {
  if (v == null) return '—';
  final s = v.toStringAsFixed(2);
  final parts = s.split('.');
  final whole = parts[0];
  final neg = whole.startsWith('-');
  final digits = neg ? whole.substring(1) : whole;
  // Indian grouping: last 3 digits, then pairs.
  final buf = StringBuffer();
  final n = digits.length;
  for (int i = 0; i < n; i++) {
    buf.write(digits[i]);
    final remaining = n - i - 1;
    if (remaining > 0) {
      if (remaining == 3 || (remaining > 3 && (remaining - 3) % 2 == 0)) {
        buf.write(',');
      }
    }
  }
  return '${neg ? '-' : ''}₹$buf.${parts[1]}';
}
