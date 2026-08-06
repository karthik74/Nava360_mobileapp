// ─────────────────────────────────────────────────────────────────────────────
//  My Goals — data models.
//
//  Mirrors the backend EmployeeAssignmentResponse (an employee's KPA/KRA/KPI
//  assignment for a performance cycle). Parsing is defensive: numbers arrive as
//  num/String/null depending on the JSON encoder.
//
//  Target vs pending target: `targetValue` is the APPROVED target the employee
//  is measured against. When they propose a change it lands in
//  `pendingTargetValue` and stays there until their supervisor approves it —
//  the employee never edits the approved figure directly.
// ─────────────────────────────────────────────────────────────────────────────

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

String _str(dynamic v) => v?.toString() ?? '';

/// How a KPI is measured. Drives the input control and its validation.
enum MeasurementType { percentage, rating, count, amount }

MeasurementType _measurementFrom(dynamic v) {
  switch (_str(v).toUpperCase()) {
    case 'RATING':
      return MeasurementType.rating;
    case 'COUNT':
      return MeasurementType.count;
    case 'AMOUNT':
      return MeasurementType.amount;
    default:
      return MeasurementType.percentage;
  }
}

extension MeasurementTypeX on MeasurementType {
  String get label => switch (this) {
        MeasurementType.percentage => 'Percentage',
        MeasurementType.rating => 'Rating',
        MeasurementType.count => 'Count',
        MeasurementType.amount => 'Amount',
      };

  /// Mirrors the backend's validateTarget so the employee sees the rule before
  /// a round-trip rather than after a rejection.
  String get hint => switch (this) {
        MeasurementType.percentage => 'Enter a percentage from 0 to 100.',
        MeasurementType.rating => 'Pick one of the configured ratings.',
        MeasurementType.count => 'Enter a whole-number count.',
        MeasurementType.amount => 'Enter an amount greater than zero.',
      };
}

/// Whether a higher or lower achievement is the better outcome.
enum TargetType { higherIsBetter, lowerIsBetter }

TargetType _targetTypeFrom(dynamic v) =>
    _str(v).toUpperCase() == 'LOWER_IS_BETTER'
        ? TargetType.lowerIsBetter
        : TargetType.higherIsBetter;

/// One selectable rating on a RATING-measured KPI.
class RatingOption {
  final String name;
  final double score;
  const RatingOption({required this.name, required this.score});

  factory RatingOption.fromJson(Map<String, dynamic> j) => RatingOption(
        name: _str(j['name']),
        score: _toDouble(j['score']) ?? 0,
      );
}

/// One assigned goal for a performance cycle.
class EmployeeGoal {
  final int id;
  final int? employeeId;

  /// Who the goal belongs to. Only meaningful on the supervisor's approval
  /// list — on My Goals it is always the signed-in employee.
  final String employeeName;
  final String employeeCode;

  final int cycleId;
  final String cycleName;
  final String kpaName;
  final String kraName;
  final String kpiName;
  final MeasurementType measurementType;
  final TargetType targetType;
  final List<RatingOption> ratingOptions;

  /// The approved target in force. Changed only by a supervisor's approval.
  final double? targetValue;

  /// A change the employee has proposed, awaiting supervisor approval.
  /// Null when there is nothing pending.
  final double? pendingTargetValue;

  final double weightage;
  final String frequency;

  const EmployeeGoal({
    required this.id,
    this.employeeId,
    this.employeeName = '',
    this.employeeCode = '',
    required this.cycleId,
    required this.cycleName,
    required this.kpaName,
    required this.kraName,
    required this.kpiName,
    required this.measurementType,
    required this.targetType,
    required this.ratingOptions,
    required this.targetValue,
    required this.pendingTargetValue,
    required this.weightage,
    required this.frequency,
  });

  bool get hasPendingChange => pendingTargetValue != null;

  factory EmployeeGoal.fromJson(Map<String, dynamic> j) => EmployeeGoal(
        id: _toInt(j['id']) ?? 0,
        employeeId: _toInt(j['employeeId']),
        employeeName: _str(j['employeeName']),
        employeeCode: _str(j['employeeCode']),
        cycleId: _toInt(j['cycleId']) ?? 0,
        cycleName: _str(j['cycleName']),
        kpaName: _str(j['kpaName']),
        kraName: _str(j['kraName']),
        kpiName: _str(j['kpiName']),
        measurementType: _measurementFrom(j['measurementType']),
        targetType: _targetTypeFrom(j['targetType']),
        ratingOptions: (j['ratingOptions'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(RatingOption.fromJson)
                .toList() ??
            const [],
        targetValue: _toDouble(j['targetValue']),
        pendingTargetValue: _toDouble(j['pendingTargetValue']),
        weightage: _toDouble(j['weightage']) ?? 0,
        frequency: _str(j['frequency']),
      );
}

/// A performance cycle. The supervisor's approval list is scoped to one.
class PerformanceCycle {
  final int id;
  final String name;

  /// DRAFT | ACTIVE | CLOSED. Targets cannot change once CLOSED.
  final String status;

  const PerformanceCycle({
    required this.id,
    required this.name,
    required this.status,
  });

  bool get isActive => status.toUpperCase() == 'ACTIVE';

  factory PerformanceCycle.fromJson(Map<String, dynamic> j) => PerformanceCycle(
        id: _toInt(j['id']) ?? 0,
        name: _str(j['name']),
        status: _str(j['status']),
      );
}

/// Human label for the cycle frequency enum.
String frequencyLabel(String raw) {
  switch (raw.toUpperCase()) {
    case 'MONTHLY':
      return 'Monthly';
    case 'QUARTERLY':
      return 'Quarterly';
    case 'HALF_YEARLY':
      return 'Half-yearly';
    case 'YEARLY':
    case 'ANNUAL':
      return 'Yearly';
    default:
      return raw.isEmpty ? '—' : raw;
  }
}

/// Trims a target for display: 12.0 → "12", 12.5 → "12.5".
String formatTarget(double? v) {
  if (v == null) return '—';
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}
