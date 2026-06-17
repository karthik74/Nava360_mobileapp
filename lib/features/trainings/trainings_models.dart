/// A participant's test/feedback status for a training.
class TrainingTestStatus {
  final int preQuestionCount;
  final int postQuestionCount;
  final int feedbackQuestionCount;
  final int? preBestPercentage;
  final int? postBestPercentage;
  final int? improvement;
  final int preAttempts;
  final int postAttempts;
  final bool feedbackSubmitted;
  final bool allowRetake;

  TrainingTestStatus({
    required this.preQuestionCount,
    required this.postQuestionCount,
    required this.feedbackQuestionCount,
    required this.preBestPercentage,
    required this.postBestPercentage,
    required this.improvement,
    required this.preAttempts,
    required this.postAttempts,
    required this.feedbackSubmitted,
    required this.allowRetake,
  });

  factory TrainingTestStatus.fromJson(Map<String, dynamic> j) => TrainingTestStatus(
        preQuestionCount: (j['preQuestionCount'] as num? ?? 0).toInt(),
        postQuestionCount: (j['postQuestionCount'] as num? ?? 0).toInt(),
        feedbackQuestionCount: (j['feedbackQuestionCount'] as num? ?? 0).toInt(),
        preBestPercentage: (j['preBestPercentage'] as num?)?.toInt(),
        postBestPercentage: (j['postBestPercentage'] as num?)?.toInt(),
        improvement: (j['improvement'] as num?)?.toInt(),
        preAttempts: (j['preAttempts'] as num? ?? 0).toInt(),
        postAttempts: (j['postAttempts'] as num? ?? 0).toInt(),
        feedbackSubmitted: j['feedbackSubmitted'] as bool? ?? false,
        allowRetake: j['allowRetake'] as bool? ?? false,
      );
}

class TQuestionOption {
  final int id;
  final String text;
  TQuestionOption({required this.id, required this.text});
  factory TQuestionOption.fromJson(Map<String, dynamic> j) =>
      TQuestionOption(id: (j['id'] as num).toInt(), text: j['text'] as String? ?? '');
}

class TQuestion {
  final int id;
  final String questionType;
  final String text;
  final bool required;
  final int? maxRating;
  final List<TQuestionOption> options;
  TQuestion({
    required this.id,
    required this.questionType,
    required this.text,
    required this.required,
    required this.maxRating,
    required this.options,
  });
  factory TQuestion.fromJson(Map<String, dynamic> j) => TQuestion(
        id: (j['id'] as num).toInt(),
        questionType: j['questionType'] as String? ?? 'SHORT_ANSWER',
        text: j['text'] as String? ?? '',
        required: j['required'] as bool? ?? false,
        maxRating: (j['maxRating'] as num?)?.toInt(),
        options: ((j['options'] as List?) ?? const [])
            .map((e) => TQuestionOption.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/** A training material — an uploaded file or an external link. */
class TrainingMaterial {
  final int id;
  final String title;
  final String? description;
  final String kind; // FILE | LINK
  final String? fileName;
  final String url; // relative /api/files/{id} for files, or absolute link

  TrainingMaterial({
    required this.id,
    required this.title,
    required this.description,
    required this.kind,
    required this.fileName,
    required this.url,
  });

  factory TrainingMaterial.fromJson(Map<String, dynamic> j) => TrainingMaterial(
        id: (j['id'] as num).toInt(),
        title: j['title'] as String? ?? 'Material',
        description: j['description'] as String?,
        kind: j['kind'] as String? ?? 'FILE',
        fileName: j['fileName'] as String?,
        url: j['url'] as String? ?? '',
      );
}

class TrainingEnrollment {
  final int id;
  final int trainingId;
  final String trainingTitle;
  final String? trainingMode;
  final String? trainingStatus;
  final String? trainingStartDate;
  final String? trainingEndDate;
  final String? trainingVenue;
  final String? trainingMeetLink;
  final String? trainingLanguage;
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
    required this.trainingVenue,
    required this.trainingMeetLink,
    required this.trainingLanguage,
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
        trainingVenue: j['trainingVenue'] as String?,
        trainingMeetLink: j['trainingMeetLink'] as String?,
        trainingLanguage: j['trainingLanguage'] as String?,
        employeeId: (j['employeeId'] as num).toInt(),
        employeeName: j['employeeName'] as String? ?? '',
        status: j['status'] as String? ?? '',
        score: (j['score'] as num? ?? 0).toInt(),
        feedback: j['feedback'] as String?,
      );
}
