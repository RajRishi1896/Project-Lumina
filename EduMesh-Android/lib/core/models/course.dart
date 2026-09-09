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
    case 'tf':
      return QuizQuestionType.trueFalse;
    case 'fill_blanks':
      return QuizQuestionType.fillBlanks;
    case 'multi_select':
    case 'multi':
      return QuizQuestionType.multiSelect;
    default:
      return QuizQuestionType.mcq;
  }
}

/// Resolves a server answer-key value to option text.
///
/// Quiz files store correct answers as option indexes (int), while the web
/// form may stringify them ("0"). A numeric string that exactly matches an
/// option is treated as literal text; otherwise a valid index resolves
/// positionally. This keeps `correct_answer: "1"` with options `["1", "2"]`
/// literal while `correct_answer: "0"` with `["Correct", "Wrong"]` maps to
/// `"Correct"` — mirroring the server grader. Out-of-range indexes yield
/// null so callers fall back to any previously parsed value. Shared by
/// [QuizQuestion.fromJson] and the quiz player's offline key injection
/// (which must run before option shuffling, or indexes map wrongly).
String? resolveAnswerOption(List<String> options, dynamic raw) {
  if (raw is int) {
    if (options.isEmpty) return null;
    return (raw >= 0 && raw < options.length) ? options[raw] : null;
  }
  if (raw is String) {
    if (options.contains(raw)) return raw;
    final idx = int.tryParse(raw.trim());
    if (idx != null) {
      if (options.isEmpty) return null;
      return (idx >= 0 && idx < options.length) ? options[idx] : null;
    }
    return raw;
  }
  return raw?.toString();
}

/// A single quiz question with its options and correct answer(s).
class QuizQuestion {
  final String id;

  final QuizQuestionType type;

  /// An optional image URL associated with the question.
  final String? image;

  /// The question text shown to the student.
  final String question;

  /// The available answer choices.
  List<String> options;

  /// The single correct answer (for mcq / trueFalse / fillBlanks).
  final String? correctAnswer;

  /// Multiple correct answers (for multiSelect).
  final List<String>? correctAnswers;

  /// An optional explanation shown after answering.
  final String? explanation;

  /// Whether the answer must match exactly (fillBlanks).
  final bool exactMatch;

  QuizQuestion({
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

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    final options = (json['options'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    String? correctAnswer =
        resolveAnswerOption(options, json['correct_answer']);
    List<String>? correctAnswers;
    final rawMulti = json['correct_answers'] ?? json['correct_answer'];
    if (rawMulti is List) {
      correctAnswers = rawMulti
          .map((e) => resolveAnswerOption(options, e) ?? e.toString())
          .toList();
    }
    return QuizQuestion(
      id: json['id']?.toString() ?? '',
      type: parseQuizQuestionType(json['type']?.toString() ?? ''),
      image: json['image'] as String?,
      question: json['question'] ?? '',
      options: options,
      correctAnswer: correctAnswer,
      correctAnswers: correctAnswers,
      explanation: json['explanation'] as String?,
      exactMatch: json['exact_match'] == true,
    );
  }

  }

/// A quiz containing a set of questions and metadata.
class Quiz {
  final String title;

  /// An optional description or instructions.
  final String? description;

  /// The time limit in minutes (0 = no limit).
  final int timeLimitMinutes;

  /// The minimum score fraction (0.0-1.0) required to pass.
  final double passThreshold;

  /// Shuffle mode: 'none', 'questions', 'options', or 'both'.
  final String shuffleMode;

  final List<QuizQuestion> questions;

  /// The version number of the quiz content.
  final int quizVersion;

  const Quiz({
    required this.title,
    this.description,
    required this.timeLimitMinutes,
    required this.passThreshold,
    required this.shuffleMode,
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
      passThreshold: ((() {
        final raw = (data['pass_threshold'] as num?)?.toDouble() ?? 0.0;
        return raw > 1.0 ? raw / 100.0 : raw;
      })()),
      shuffleMode: data['shuffle_mode'] as String? ??
          ((data['shuffle_questions'] == true || data['shuffle'] == true) ? 'both' : 'none'),
      questions: (data['questions'] as List<dynamic>?)
              ?.map((e) =>
                  QuizQuestion.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      quizVersion: (data['quiz_version'] as num?)?.toInt() ?? 1,
    );
  }
}

/// A resource belonging to a course.
class CourseResource {
  final String id;

  /// The ID of the course this resource belongs to.
  final String courseId;

  final CourseType resourceType;

  final String title;

  /// The original upload filename.
  final String? originalName;

  /// The server-side filename.
  final String? filename;

  /// The file size in bytes.
  final int fileSize;

  /// The page count for PDF-type resources (0 when unknown).
  final int pageCount;

  /// The duration in seconds for video resources (0 when unknown).
  final int durationSeconds;

  final int position;

  const CourseResource({
    required this.id,
    required this.courseId,
    required this.resourceType,
    required this.title,
    this.originalName,
    this.filename,
    required this.fileSize,
    this.pageCount = 0,
    this.durationSeconds = 0,
    required this.position,
  });

  bool get isQuiz => resourceType == CourseType.quiz;

  factory CourseResource.fromJson(Map<String, dynamic> json) {
    return CourseResource(
      id: json['id']?.toString() ?? '',
      courseId: json['course_id']?.toString() ?? '',
      resourceType: _parseCourseType(json['resource_type']?.toString() ?? ''),
      title: json['title'] ?? '',
      originalName: json['original_name'] as String?,
      filename: json['filename'] as String?,
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      pageCount: (json['page_count'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
      position: (json['position'] as num?)?.toInt() ?? 0,
    );
  }

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
  //: Fields

  final String id;

  final String title;

  /// An optional description of the course.
  final String? description;

  final String subject;

  final int grade;

  /// The ISO 639-1 language code.
  final String language;

  /// Optional URL to a cover image.
  final String? coverImage;

  /// Published status (0 = draft, 1 = published).
  final int published;

  /// The username of the teacher who created this course.
  final String? teacherUsername;

  /// ISO 8601 creation timestamp.
  final String? createdAt;

  /// ISO 8601 last-update timestamp.
  final String? updatedAt;

  /// The resources within this course (may be null if not loaded).
  final List<CourseResource>? resources;

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
    this.createdAt,
    this.updatedAt,
    this.resources,
  });

  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      description: json['description'] as String?,
      subject: json['subject'] ?? '',
      grade: num.tryParse(json['grade']?.toString() ?? '')?.toInt() ?? 0,
      language: json['language'] ?? 'en',
      coverImage: json['cover_image'] as String?,
      published: num.tryParse(json['published']?.toString() ?? '')?.toInt() ?? 0,
      teacherUsername: json['teacher_username'] as String?,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      resources: (json['resources'] as List<dynamic>?)
          ?.map((e) => CourseResource.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
