import '../recommendation/on_device_scorer.dart';

/// The type of a course resource.
enum CourseType {
  /// Textbooks and reference books.
  textbook,
  /// Video lectures and recordings.
  video,
  /// Interactive quizzes.
  quiz,
  /// Past examination papers.
  pastPaper,
}

/// The type of a quiz question.
enum QuizQuestionType {
  /// Multiple choice (single correct answer).
  mcq,
  /// True / False.
  trueFalse,
  /// Fill-in-the-blanks.
  fillBlanks,
  /// Multiple select (multiple correct answers).
  multiSelect,
}

/// Parses a string into a [QuizQuestionType] value.
QuizQuestionType parseQuizQuestionType(String s) {
  switch (s) {
    case 'mcq':
      return QuizQuestionType.mcq;
    case 'true_false':
      return QuizQuestionType.trueFalse;
    case 'fill_blanks':
      return QuizQuestionType.fillBlanks;
    case 'multi_select':
      return QuizQuestionType.multiSelect;
    default:
      return QuizQuestionType.mcq;
  }
}

/// Returns the wire string representation of a [QuizQuestionType].
String quizQuestionTypeToShortString(QuizQuestionType type) {
  switch (type) {
    case QuizQuestionType.mcq:
      return 'mcq';
    case QuizQuestionType.trueFalse:
      return 'true_false';
    case QuizQuestionType.fillBlanks:
      return 'fill_blanks';
    case QuizQuestionType.multiSelect:
      return 'multi_select';
  }
}

/// A single quiz question with its options and correct answer(s).
class QuizQuestion {
  /// The unique identifier for this question.
  final String id;

  /// The type of question.
  final QuizQuestionType type;

  /// An optional image URL associated with the question.
  final String? image;

  /// The question text shown to the student.
  final String question;

  /// The available answer choices.
  final List<String> options;

  /// The single correct answer (for mcq / trueFalse / fillBlanks).
  final String? correctAnswer;

  /// Multiple correct answers (for multiSelect).
  final List<String>? correctAnswers;

  /// An optional explanation shown after answering.
  final String? explanation;

  /// Whether the answer must match exactly (fillBlanks).
  final bool exactMatch;

  /// Creates a [QuizQuestion] with the given data.
  const QuizQuestion({
    required this.id,
    required this.type,
    this.image,
    required this.question,
    required this.options,
    this.correctAnswer,
    this.correctAnswers,
    this.explanation,
    this.exactMatch = false,
  });

  /// Creates a [QuizQuestion] from a JSON [map].
  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    return QuizQuestion(
      id: json['id']?.toString() ?? '',
      type: parseQuizQuestionType(json['type']?.toString() ?? ''),
      image: json['image'] as String?,
      question: json['question'] ?? '',
      options: (json['options'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      correctAnswer: json['correct_answer'] as String?,
      correctAnswers: (json['correct_answers'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      explanation: json['explanation'] as String?,
      exactMatch: json['exact_match'] == true,
    );
  }

  /// Serializes this [QuizQuestion] to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': quizQuestionTypeToShortString(type),
    if (image != null) 'image': image,
    'question': question,
    'options': options,
    if (correctAnswer != null) 'correct_answer': correctAnswer,
    if (correctAnswers != null) 'correct_answers': correctAnswers,
    if (explanation != null) 'explanation': explanation,
    'exact_match': exactMatch,
  };
}

/// A quiz containing a set of questions and metadata.
class Quiz {
  /// The display title of the quiz.
  final String title;

  /// An optional description or instructions.
  final String? description;

  /// The time limit in minutes (0 = no limit).
  final int timeLimitMinutes;

  /// The minimum score fraction (0.0–1.0) required to pass.
  final double passThreshold;

  /// The maximum number of attempts allowed.
  final int maxAttempts;

  /// Whether to shuffle the question order.
  final bool shuffleQuestions;

  /// The list of questions in this quiz.
  final List<QuizQuestion> questions;

  /// The version number of the quiz content.
  final int quizVersion;

  /// Creates a [Quiz] with the given data.
  const Quiz({
    required this.title,
    this.description,
    required this.timeLimitMinutes,
    required this.passThreshold,
    required this.maxAttempts,
    required this.shuffleQuestions,
    required this.questions,
    required this.quizVersion,
  });

  /// Creates a [Quiz] from a JSON [map], reading from `json['quiz']`.
  factory Quiz.fromJson(Map<String, dynamic> json) {
    final data = json['quiz'] as Map<String, dynamic>? ?? json;
    return Quiz(
      title: data['title'] ?? '',
      description: data['description'] as String?,
      timeLimitMinutes: (data['time_limit_minutes'] as num?)?.toInt() ?? 0,
      passThreshold: (data['pass_threshold'] as num?)?.toDouble() ?? 0.0,
      maxAttempts: (data['max_attempts'] as num?)?.toInt() ?? 1,
      shuffleQuestions: data['shuffle_questions'] == true,
      questions: (data['questions'] as List<dynamic>?)
              ?.map((e) =>
                  QuizQuestion.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      quizVersion: (data['quiz_version'] as num?)?.toInt() ?? 1,
    );
  }

  /// Serializes this [Quiz] to a JSON-compatible map, wrapped in `{'quiz': ...}`.
  Map<String, dynamic> toJson() => {
    'quiz': {
      'title': title,
      if (description != null) 'description': description,
      'time_limit_minutes': timeLimitMinutes,
      'pass_threshold': passThreshold,
      'max_attempts': maxAttempts,
      'shuffle_questions': shuffleQuestions,
      'questions': questions.map((q) => q.toJson()).toList(),
      'quiz_version': quizVersion,
    },
  };
}

/// A resource belonging to a course.
class CourseResource {
  /// The unique identifier for this resource.
  final String id;

  /// The ID of the course this resource belongs to.
  final String courseId;

  /// The type of resource.
  final CourseType resourceType;

  /// The display title.
  final String title;

  /// The original upload filename.
  final String? originalName;

  /// The server-side filename.
  final String? filename;

  /// The file size in bytes.
  final int fileSize;

  /// The display order position within the course.
  final int position;

  /// Creates a [CourseResource] with the given data.
  const CourseResource({
    required this.id,
    required this.courseId,
    required this.resourceType,
    required this.title,
    this.originalName,
    this.filename,
    required this.fileSize,
    required this.position,
  });

  /// The file extension extracted from [filename], lowercased.
  /// Returns an empty string if [filename] is null or has no extension.
  String get extension {
    if (filename == null) return '';
    final dot = filename!.lastIndexOf('.');
    return dot == -1 ? '' : filename!.substring(dot + 1).toLowerCase();
  }

  /// Whether this resource is a quiz.
  bool get isQuiz => resourceType == CourseType.quiz;

  /// Creates a [CourseResource] from a JSON [map].
  factory CourseResource.fromJson(Map<String, dynamic> json) {
    return CourseResource(
      id: json['id']?.toString() ?? '',
      courseId: json['course_id']?.toString() ?? '',
      resourceType: _parseCourseType(json['resource_type']?.toString() ?? ''),
      title: json['title'] ?? '',
      originalName: json['original_name'] as String?,
      filename: json['filename'] as String?,
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      position: (json['position'] as num?)?.toInt() ?? 0,
    );
  }

  /// Serializes this [CourseResource] to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'id': id,
    'course_id': courseId,
    'resource_type': resourceType.name,
    'title': title,
    if (originalName != null) 'original_name': originalName,
    if (filename != null) 'filename': filename,
    'file_size': fileSize,
    'position': position,
  };

  /// Internal helper: maps a string to [CourseType].
  static CourseType _parseCourseType(String s) {
    switch (s.toLowerCase()) {
      case 'textbook':
        return CourseType.textbook;
      case 'video':
        return CourseType.video;
      case 'quiz':
        return CourseType.quiz;
      case 'pastpaper':
      case 'past_paper':
        return CourseType.pastPaper;
      default:
        return CourseType.textbook;
    }
  }
}

/// A course containing metadata and optionally its resources.
class Course {
  /// Returns the cluster name for this course's subject.
  /// Delegates to [OnDeviceScorer.clusterOf] as single source of truth.
  String get cluster => OnDeviceScorer.clusterOf(subject);

  // -- Fields --

  /// The unique identifier for this course.
  final String id;

  /// The display title of the course.
  final String title;

  /// An optional description of the course.
  final String? description;

  /// The subject this course belongs to.
  final String subject;

  /// The grade or class level.
  final int grade;

  /// The ISO 639-1 language code.
  final String language;

  /// Optional URL to a cover image.
  final String? coverImage;

  /// Published status (0 = draft, 1 = published).
  final int published;

  /// The username of the teacher who created this course.
  final String? teacherUsername;

  /// The number of enrolled students.
  final int enrollmentCount;

  /// ISO 8601 creation timestamp.
  final String? createdAt;

  /// ISO 8601 last-update timestamp.
  final String? updatedAt;

  /// The resources within this course (may be null if not loaded).
  final List<CourseResource>? resources;

  /// IDs of similar courses for recommendations.
  final List<String>? similarCourseIds;

  /// Creates a [Course] with the given data.
  const Course({
    required this.id,
    required this.title,
    this.description,
    required this.subject,
    required this.grade,
    required this.language,
    this.coverImage,
    required this.published,
    this.teacherUsername,
    this.enrollmentCount = 0,
    this.createdAt,
    this.updatedAt,
    this.resources,
    this.similarCourseIds,
  });

  /// Creates a [Course] from a JSON [map].
  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      description: json['description'] as String?,
      subject: json['subject'] ?? '',
      grade: (json['grade'] as num?)?.toInt() ?? 0,
      language: json['language'] ?? 'en',
      coverImage: json['cover_image'] as String?,
      published: (json['published'] as num?)?.toInt() ?? 0,
      teacherUsername: json['teacher_username'] as String?,
      enrollmentCount: (json['enrollment_count'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      resources: (json['resources'] as List<dynamic>?)
          ?.map((e) => CourseResource.fromJson(e as Map<String, dynamic>))
          .toList(),
      similarCourseIds: (json['similar_course_ids'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
    );
  }

  /// Serializes this [Course] to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    if (description != null) 'description': description,
    'subject': subject,
    'grade': grade,
    'language': language,
    if (coverImage != null) 'cover_image': coverImage,
    'published': published,
    if (teacherUsername != null) 'teacher_username': teacherUsername,
    'enrollment_count': enrollmentCount,
    if (createdAt != null) 'created_at': createdAt,
    if (updatedAt != null) 'updated_at': updatedAt,
    if (resources != null)
      'resources': resources!.map((r) => r.toJson()).toList(),
    if (similarCourseIds != null) 'similar_course_ids': similarCourseIds,
  };
}

/// A student's attempt at a quiz, including answers and scoring.
class QuizAttempt {
  /// The unique identifier for this attempt.
  final String id;

  /// The student's user ID.
  final String studentId;

  /// The course this attempt belongs to.
  final String courseId;

  /// The resource (quiz) ID.
  final String resourceId;

  /// The attempt number (1-based).
  final int attemptNumber;

  /// The score achieved (0.0–1.0).
  final double score;

  /// Whether the attempt met the pass threshold.
  final bool passed;

  /// JSON-encoded answers payload.
  final String? answersJson;

  /// ISO 8601 timestamp when the attempt started.
  final String? startedAt;

  /// ISO 8601 timestamp when the attempt was submitted.
  final String? submittedAt;

  /// Time taken in seconds.
  final int timeTakenSeconds;

  /// The quiz version at the time of this attempt.
  final int quizVersion;

  /// The pass threshold in effect when submitted.
  final double thresholdAtSubmission;

  /// Sync status for offline queue (0 = pending, 1 = synced, 2 = conflict).
  final int syncStatus;

  /// Creates a [QuizAttempt] with the given data.
  const QuizAttempt({
    required this.id,
    required this.studentId,
    required this.courseId,
    required this.resourceId,
    required this.attemptNumber,
    required this.score,
    required this.passed,
    this.answersJson,
    this.startedAt,
    this.submittedAt,
    required this.timeTakenSeconds,
    required this.quizVersion,
    required this.thresholdAtSubmission,
    this.syncStatus = 0,
  });

  /// Creates a [QuizAttempt] from a JSON [map].
  factory QuizAttempt.fromJson(Map<String, dynamic> json) {
    return QuizAttempt(
      id: json['id']?.toString() ?? '',
      studentId: json['student_id']?.toString() ?? '',
      courseId: json['course_id']?.toString() ?? '',
      resourceId: json['resource_id']?.toString() ?? '',
      attemptNumber: (json['attempt_number'] as num?)?.toInt() ?? 0,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      passed: json['passed'] == true,
      answersJson: json['answers_json'] as String?,
      startedAt: json['started_at'] as String?,
      submittedAt: json['submitted_at'] as String?,
      timeTakenSeconds: (json['time_taken_seconds'] as num?)?.toInt() ?? 0,
      quizVersion: (json['quiz_version'] as num?)?.toInt() ?? 1,
      thresholdAtSubmission:
          (json['threshold_at_submission'] as num?)?.toDouble() ?? 0.0,
      syncStatus: (json['sync_status'] as num?)?.toInt() ?? 0,
    );
  }

  /// Serializes this [QuizAttempt] to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'id': id,
    'student_id': studentId,
    'course_id': courseId,
    'resource_id': resourceId,
    'attempt_number': attemptNumber,
    'score': score,
    'passed': passed,
    if (answersJson != null) 'answers_json': answersJson,
    if (startedAt != null) 'started_at': startedAt,
    if (submittedAt != null) 'submitted_at': submittedAt,
    'time_taken_seconds': timeTakenSeconds,
    'quiz_version': quizVersion,
    'threshold_at_submission': thresholdAtSubmission,
    'sync_status': syncStatus,
  };
}

/// A link between a course and a similar course.
class SimilarLink {
  /// The source course ID.
  final String courseId;

  /// The recommended similar course ID.
  final String similarCourseId;

  /// Creates a [SimilarLink] with the given data.
  const SimilarLink({
    required this.courseId,
    required this.similarCourseId,
  });

  /// Creates a [SimilarLink] from a JSON [map].
  factory SimilarLink.fromJson(Map<String, dynamic> json) {
    return SimilarLink(
      courseId: json['course_id']?.toString() ?? '',
      similarCourseId: json['similar_course_id']?.toString() ?? '',
    );
  }

  /// Serializes this [SimilarLink] to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'course_id': courseId,
    'similar_course_id': similarCourseId,
  };
}
