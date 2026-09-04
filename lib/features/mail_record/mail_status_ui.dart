import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'mail_models.dart';

/// (color, label) tone for a mail-type entry (`AdminMailType`).
StatusTone mailTypeTone(String mailType) {
  switch (mailType.toUpperCase()) {
    case MailType.outward:
      return const StatusTone(AppColors.warning, 'Outward');
    case MailType.inward:
    default:
      return const StatusTone(AppColors.info, 'Inward');
  }
}

/// (color, label) tone for a branch-month audit status
/// (`AdminMailAuditStatus` — PENDING → IN_PROGRESS → COMPLETED).
StatusTone mailAuditStatusTone(String status) {
  switch (status.toUpperCase()) {
    case MailAuditStatus.pending:
      return const StatusTone(AppColors.muted, 'Pending');
    case MailAuditStatus.inProgress:
      return const StatusTone(AppColors.info, 'In progress');
    case MailAuditStatus.completed:
      return const StatusTone(AppColors.success, 'Completed');
    default:
      return StatusTone(AppColors.muted, status);
  }
}

/// (color, label) tone for a stationery-shipment status
/// (`AdminMailShipmentStatus` — DISPATCHED → PARTIALLY_RECEIVED → RECEIVED).
StatusTone mailShipmentStatusTone(String status) {
  switch (status.toUpperCase()) {
    case MailShipmentStatus.dispatched:
      return const StatusTone(AppColors.warning, 'Dispatched');
    case MailShipmentStatus.partiallyReceived:
      return const StatusTone(AppColors.info, 'Partially received');
    case MailShipmentStatus.received:
      return const StatusTone(AppColors.success, 'Received');
    default:
      return StatusTone(AppColors.muted, status);
  }
}

/// (color, label) tone for a complaint status
/// (`AdminComplaintStatus` — PENDING → IN_PROGRESS →
/// RESOLVED/ESCALATED/REJECTED).
StatusTone mailComplaintStatusTone(String status) {
  switch (status.toUpperCase()) {
    case MailComplaintStatus.pending:
      return const StatusTone(AppColors.muted, 'Pending');
    case MailComplaintStatus.inProgress:
      return const StatusTone(AppColors.info, 'In progress');
    case MailComplaintStatus.resolved:
      return const StatusTone(AppColors.success, 'Resolved');
    case MailComplaintStatus.escalated:
      return const StatusTone(AppColors.warning, 'Escalated');
    case MailComplaintStatus.rejected:
      return const StatusTone(AppColors.danger, 'Rejected');
    default:
      return StatusTone(AppColors.muted, status);
  }
}

/// Human label for a complaint-status enum value, for the
/// "change status…" picker (mirrors [mailComplaintStatusTone]'s labels).
String mailComplaintStatusLabel(String status) => mailComplaintStatusTone(status).label;

/// (color, label) tone for a mail audit-trail action
/// (`AdminMailAuditLog.action`, e.g. `CREATE`/`UPDATE`/`DELETE`).
StatusTone mailAuditActionTone(String action) {
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

/// Icon for a mail record's list-card thumbnail / detail header.
const IconData mailRecordIcon = Icons.mail_rounded;

/// Icon for a stationery shipment's list-card thumbnail.
const IconData mailShipmentIcon = Icons.local_shipping_rounded;

/// Icon for a complaint's list-card thumbnail.
const IconData mailComplaintIcon = Icons.report_problem_rounded;
