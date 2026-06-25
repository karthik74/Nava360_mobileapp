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

/// A master-data option (department / designation) from `GET /api/lookups/{category}`.
class LookupOption {
  final int id;
  final String? code;
  final String label;

  const LookupOption({required this.id, required this.code, required this.label});

  factory LookupOption.fromJson(Map<String, dynamic> j) => LookupOption(
        id: (j['id'] as num).toInt(),
        code: j['code'] as String?,
        label: (j['label'] as String?) ?? (j['code'] as String?) ?? '',
      );
}

/// Lightweight requisition view from list responses.
class RequisitionSummary {
  final int id;
  final String title;
  final String? department;
  final String? designation;
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
    required this.designation,
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
        designation: j['designation'] as String?,
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

/// Aggregated requisition dashboard, from `GET /api/requisitions/summary`.
class RequisitionDashboard {
  final String scope; // ALL | HIERARCHY | MINE
  final int totalRequisitions;
  final Map<String, int> statusCounts; // DRAFT/OPEN/ON_HOLD/CLOSED
  final Map<String, int> priorityCounts; // LOW/MEDIUM/HIGH/URGENT
  final int totalPositions;
  final int openPositions;
  final int filledPositions;
  final int remainingPositions;
  final Map<String, int> pipeline; // candidate stage -> count
  final int candidatesInPipeline;
  final int hiredCount;
  final int overdueCount;
  final List<BranchBreakdown> byBranch;
  final List<DesignationBreakdown> byDesignation;
  final List<RequisitionSummary> attention;

  const RequisitionDashboard({
    required this.scope,
    required this.totalRequisitions,
    required this.statusCounts,
    required this.priorityCounts,
    required this.totalPositions,
    required this.openPositions,
    required this.filledPositions,
    required this.remainingPositions,
    required this.pipeline,
    required this.candidatesInPipeline,
    required this.hiredCount,
    required this.overdueCount,
    required this.byBranch,
    required this.byDesignation,
    required this.attention,
  });

  static Map<String, int> _intMap(dynamic v) {
    final m = (v as Map?) ?? const {};
    return m.map((k, val) =>
        MapEntry(k.toString(), (val as num?)?.toInt() ?? 0));
  }

  factory RequisitionDashboard.fromJson(Map<String, dynamic> j) =>
      RequisitionDashboard(
        scope: (j['scope'] as String?) ?? 'MINE',
        totalRequisitions: (j['totalRequisitions'] as num?)?.toInt() ?? 0,
        statusCounts: _intMap(j['statusCounts']),
        priorityCounts: _intMap(j['priorityCounts']),
        totalPositions: (j['totalPositions'] as num?)?.toInt() ?? 0,
        openPositions: (j['openPositions'] as num?)?.toInt() ?? 0,
        filledPositions: (j['filledPositions'] as num?)?.toInt() ?? 0,
        remainingPositions: (j['remainingPositions'] as num?)?.toInt() ?? 0,
        pipeline: _intMap(j['pipeline']),
        candidatesInPipeline: (j['candidatesInPipeline'] as num?)?.toInt() ?? 0,
        hiredCount: (j['hiredCount'] as num?)?.toInt() ?? 0,
        overdueCount: (j['overdueCount'] as num?)?.toInt() ?? 0,
        byBranch: ((j['byBranch'] as List?) ?? const [])
            .map((e) => BranchBreakdown.fromJson(e as Map<String, dynamic>))
            .toList(),
        byDesignation: ((j['byDesignation'] as List?) ?? const [])
            .map((e) => DesignationBreakdown.fromJson(e as Map<String, dynamic>))
            .toList(),
        attention: ((j['attention'] as List?) ?? const [])
            .map((e) => RequisitionSummary.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// Human label for the scope, for the dashboard subtitle.
  String get scopeLabel {
    switch (scope) {
      case 'ALL':
        return 'All branches';
      case 'HIERARCHY':
        return 'Your branches';
      default:
        return 'Your requisitions';
    }
  }
}

/// One branch's contribution to the dashboard rollup.
class BranchBreakdown {
  final int? branchId;
  final String? branchLabel;
  final String? areaLabel;
  final String? divisionLabel;
  final String? regionLabel;
  final int requisitions;
  final int openPositions;

  const BranchBreakdown({
    required this.branchId,
    required this.branchLabel,
    required this.areaLabel,
    required this.divisionLabel,
    required this.regionLabel,
    required this.requisitions,
    required this.openPositions,
  });

  factory BranchBreakdown.fromJson(Map<String, dynamic> j) => BranchBreakdown(
        branchId: (j['branchId'] as num?)?.toInt(),
        branchLabel: j['branchLabel'] as String?,
        areaLabel: j['areaLabel'] as String?,
        divisionLabel: j['divisionLabel'] as String?,
        regionLabel: j['regionLabel'] as String?,
        requisitions: (j['requisitions'] as num?)?.toInt() ?? 0,
        openPositions: (j['openPositions'] as num?)?.toInt() ?? 0,
      );

  String get name => branchLabel ?? 'No branch';

  /// "Region · Division · Area" context line (omits empty parts).
  String get hierarchy => [regionLabel, divisionLabel, areaLabel]
      .where((s) => s != null && s.trim().isNotEmpty)
      .join(' · ');
}

/// One designation's contribution to the dashboard rollup.
class DesignationBreakdown {
  final String designation;
  final int requisitions;
  final int openPositions;

  const DesignationBreakdown({
    required this.designation,
    required this.requisitions,
    required this.openPositions,
  });

  factory DesignationBreakdown.fromJson(Map<String, dynamic> j) =>
      DesignationBreakdown(
        designation: (j['designation'] as String?) ?? '—',
        requisitions: (j['requisitions'] as num?)?.toInt() ?? 0,
        openPositions: (j['openPositions'] as num?)?.toInt() ?? 0,
      );
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
  final String? designation;
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
    this.designation,
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
      'designation': trimOrNull(designation),
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
