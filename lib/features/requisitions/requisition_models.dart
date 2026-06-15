import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Experience bracket — mirrors backend `ExperienceLevel`.
enum ExperienceLevel {
  entry('ENTRY', 'Entry'),
  mid('MID', 'Mid'),
  senior('SENIOR', 'Senior'),
  lead('LEAD', 'Lead');

  const ExperienceLevel(this.wire, this.label);
  final String wire;
  final String label;

  static ExperienceLevel? fromWire(String? v) {
    for (final e in values) {
      if (e.wire == v) return e;
    }
    return null;
  }
}

/// Hiring urgency — mirrors backend `RequisitionPriority`.
enum RequisitionPriority {
  low('LOW', 'Low'),
  medium('MEDIUM', 'Medium'),
  high('HIGH', 'High'),
  urgent('URGENT', 'Urgent');

  const RequisitionPriority(this.wire, this.label);
  final String wire;
  final String label;

  static RequisitionPriority? fromWire(String? v) {
    for (final e in values) {
      if (e.wire == v) return e;
    }
    return null;
  }

  Color get color {
    switch (this) {
      case RequisitionPriority.low:
        return AppColors.muted;
      case RequisitionPriority.medium:
        return AppColors.info;
      case RequisitionPriority.high:
        return AppColors.warning;
      case RequisitionPriority.urgent:
        return AppColors.danger;
    }
  }
}

/// Lightweight requisition view from list responses.
class RequisitionSummary {
  final int id;
  final String title;
  final String? department;
  final String? branchLabel;
  final int numberOfPositions;
  final ExperienceLevel? experienceLevel;
  final RequisitionPriority? priority;
  final String status; // DRAFT | OPEN | ON_HOLD | CLOSED
  final String? targetDate;
  final String? createdByName;

  const RequisitionSummary({
    required this.id,
    required this.title,
    required this.department,
    required this.branchLabel,
    required this.numberOfPositions,
    required this.experienceLevel,
    required this.priority,
    required this.status,
    required this.targetDate,
    required this.createdByName,
  });

  factory RequisitionSummary.fromJson(Map<String, dynamic> j) =>
      RequisitionSummary(
        id: (j['id'] as num).toInt(),
        title: (j['title'] as String?) ?? 'Untitled',
        department: j['department'] as String?,
        branchLabel: j['branchLabel'] as String?,
        numberOfPositions: (j['numberOfPositions'] as num?)?.toInt() ?? 1,
        experienceLevel:
            ExperienceLevel.fromWire(j['experienceLevel'] as String?),
        priority: RequisitionPriority.fromWire(j['priority'] as String?),
        status: (j['status'] as String?) ?? 'DRAFT',
        targetDate: j['targetDate'] as String?,
        createdByName: j['createdByName'] as String?,
      );

  StatusTone get statusTone {
    switch (status) {
      case 'OPEN':
        return const StatusTone(AppColors.success, 'Open');
      case 'ON_HOLD':
        return const StatusTone(AppColors.warning, 'On hold');
      case 'CLOSED':
        return const StatusTone(AppColors.muted, 'Closed');
      default:
        return const StatusTone(AppColors.info, 'Draft');
    }
  }
}

/// A selectable branch (with its org hierarchy), from `GET /api/org/branches`.
class BranchOption {
  final int id;
  final String? code;
  final String label;
  final String? areaLabel;
  final String? divisionLabel;
  final String? regionLabel;
  final bool active;

  const BranchOption({
    required this.id,
    required this.code,
    required this.label,
    required this.areaLabel,
    required this.divisionLabel,
    required this.regionLabel,
    required this.active,
  });

  factory BranchOption.fromJson(Map<String, dynamic> j) => BranchOption(
        id: (j['id'] as num).toInt(),
        code: j['code'] as String?,
        label: (j['label'] as String?) ?? (j['code'] as String?) ?? 'Branch',
        areaLabel: j['areaLabel'] as String?,
        divisionLabel: j['divisionLabel'] as String?,
        regionLabel: j['regionLabel'] as String?,
        active: j['active'] != false,
      );

  /// "Region · Division · Area" context line (omits empty parts).
  String get hierarchy => [
        regionLabel,
        divisionLabel,
        areaLabel,
      ].where((s) => s != null && s.trim().isNotEmpty).join(' · ');
}

/// Payload for creating a requisition — mirrors backend `RequisitionRequest`.
class NewRequisition {
  final String title;
  final String? department;
  final int? branchId;
  final int numberOfPositions;
  final String? jobDescription;
  final String? requiredSkills;
  final ExperienceLevel? experienceLevel;
  final RequisitionPriority? priority;
  final String? targetDate; // ISO yyyy-MM-dd
  final String? notes;

  const NewRequisition({
    required this.title,
    this.department,
    this.branchId,
    this.numberOfPositions = 1,
    this.jobDescription,
    this.requiredSkills,
    this.experienceLevel,
    this.priority,
    this.targetDate,
    this.notes,
  });

  Map<String, dynamic> toJson() {
    String? trimOrNull(String? s) {
      final t = s?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    return {
      'title': title.trim(),
      'department': trimOrNull(department),
      'branchId': branchId,
      'numberOfPositions': numberOfPositions,
      'jobDescription': trimOrNull(jobDescription),
      'requiredSkills': trimOrNull(requiredSkills),
      'experienceLevel': experienceLevel?.wire,
      'priority': priority?.wire,
      'targetDate': targetDate,
      'notes': trimOrNull(notes),
    };
  }
}
