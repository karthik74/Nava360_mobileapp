class TrainingEnrollment {
  final int id;
  final int trainingId;
  final String trainingTitle;
  final String? trainingMode;
  final String? trainingStatus;
  final String? trainingStartDate;
  final String? trainingEndDate;
  final int employeeId;
  final String employeeName;
  final String status;
  final int score;
  final String? feedback;

  TrainingEnrollment({
    required this.id,
    required this.trainingId,
    required this.trainingTitle,
    required this.trainingMode,
    required this.trainingStatus,
    required this.trainingStartDate,
    required this.trainingEndDate,
    required this.employeeId,
    required this.employeeName,
    required this.status,
    required this.score,
    required this.feedback,
  });

  factory TrainingEnrollment.fromJson(Map<String, dynamic> j) => TrainingEnrollment(
        id: (j['id'] as num).toInt(),
        trainingId: (j['trainingId'] as num).toInt(),
        trainingTitle: j['trainingTitle'] as String? ?? '',
        trainingMode: j['trainingMode'] as String?,
        trainingStatus: j['trainingStatus'] as String?,
        trainingStartDate: j['trainingStartDate'] as String?,
        trainingEndDate: j['trainingEndDate'] as String?,
        employeeId: (j['employeeId'] as num).toInt(),
        employeeName: j['employeeName'] as String? ?? '',
        status: j['status'] as String? ?? '',
        score: (j['score'] as num? ?? 0).toInt(),
        feedback: j['feedback'] as String?,
      );
}
