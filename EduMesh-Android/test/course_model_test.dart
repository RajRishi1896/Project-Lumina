// Model tests folded from test/fix_regressions_test.dart (deleted 2026-08):
// CourseResource.fromJson (course-player offline fallback path) and the
// FlashcardDeck.subject default contract.
//
// Contracts verified against lib source on 2026-08:
// - CourseResource.fromJson key names from lib/core/models/course.dart.
// - FlashcardDeck has NO fromJson/toJson: persistence is SQLite row maps in
//   flashcard_service.dart using `(row['subject'] ?? '').toString()`.
import 'package:flutter_test/flutter_test.dart';

import 'package:edumesh_android/core/models/course.dart';
import 'package:edumesh_android/core/models/flashcard_models.dart';

void main() {
  group('CourseResource.fromJson (course-player local-table fallback)', () {
    test('parses every field from a full local course_resources row map', () {
      final r = CourseResource.fromJson(const {
        'id': 42,
        'course_id': 7,
        'resource_type': 'video',
        'title': 'Photosynthesis lecture',
        'original_name': 'lecture-01.mp4',
        'filename': 'a3f2e1b0.mp4',
        'file_size': 10485760,
        'page_count': 0,
        'duration_seconds': 615,
        'position': 3,
      });
      expect(r.id, '42'); // ints are stringified via toString
      expect(r.courseId, '7');
      expect(r.resourceType, CourseType.videos); // 'video' is a deprecated alias for videos
      expect(r.title, 'Photosynthesis lecture');
      expect(r.originalName, 'lecture-01.mp4');
      expect(r.filename, 'a3f2e1b0.mp4');
      expect(r.fileSize, 10485760);
      expect(r.pageCount, 0);
      expect(r.durationSeconds, 615);
      expect(r.position, 3);
      expect(r.isQuiz, isFalse);
    });

    test('missing optional fields fall back to safe defaults', () {
      final r = CourseResource.fromJson(const {});
      expect(r.id, '');
      expect(r.courseId, '');
      expect(r.resourceType, CourseType.textbook); // unknown/absent type default
      expect(r.title, '');
      expect(r.originalName, isNull);
      expect(r.filename, isNull);
      expect(r.fileSize, 0);
      expect(r.pageCount, 0);
      expect(r.durationSeconds, 0);
      expect(r.position, 0);
    });

    test('resource_type parsing: case-insensitive, aliases, pyq/pastPaper distinct', () {
      int typeOf(String raw) => CourseResource.fromJson({'resource_type': raw}).resourceType.index;
      expect(typeOf('TEXTBOOK'), CourseType.textbook.index);
      expect(typeOf('Video'), CourseType.videos.index);
      expect(typeOf('videos'), CourseType.videos.index);
      expect(typeOf('khan'), CourseType.videos.index);
      expect(typeOf('quiz'), CourseType.quiz.index);
      expect(typeOf('pyq'), CourseType.pyq.index);
      expect(typeOf('notes'), CourseType.notes.index);
      expect(typeOf('kiwix'), CourseType.kiwix.index);
      expect(typeOf('past_paper'), CourseType.pastPaper.index);
      expect(typeOf('pastpaper'), CourseType.pastPaper.index);
      expect(typeOf('document'), CourseType.textbook.index);
      expect(typeOf('image'), CourseType.textbook.index);
      expect(typeOf('archive'), CourseType.textbook.index);
      expect(typeOf('mystery'), CourseType.textbook.index);
      // pyq and pastPaper are DISTINCT values (manage-content maps the
      // pastPaper badge to PYQ, but the stored types differ).
      expect(CourseType.pyq.index, isNot(CourseType.pastPaper.index));
    });

    test('quiz resources report isQuiz', () {
      final r = CourseResource.fromJson(const {'resource_type': 'quiz', 'title': 'Unit test'});
      expect(r.isQuiz, isTrue);
    });
  });

  group('FlashcardDeck.subject default', () {    test('constructor defaults subject to empty string', () {
      const deck = FlashcardDeck(
        id: 'deck-1',
        title: 'Biology basics',
        source: 'local',
        cards: [],
      );
      expect(deck.subject, '');
    });

    test('explicit subject is preserved', () {
      const deck = FlashcardDeck(
        id: 'deck-2',
        title: 'Kannada vocabulary',
        source: 'hub',
        cards: [],
        subject: 'Kannada',
      );
      expect(deck.subject, 'Kannada');
    });

    test('SQLite row mapping used by FlashcardService preserves subject and defaults when absent', () {
      // Mirrors flashcard_service.dart's real deserialization expression:
      // `subject: (row['subject'] ?? '').toString()`.
      String subjectFromRow(Map<String, dynamic> row) => (row['subject'] ?? '').toString();

      expect(subjectFromRow({'subject': 'History'}), 'History');
      expect(subjectFromRow({}), ''); // pre-migration row without the column
      expect(subjectFromRow({'subject': null}), '');
    });
  });

  group('Course row grade/published parsing (courses table cache)', () {
    // Mirrors CourseService._rowToCourse's real deserialization expressions:
    // the grade column is TEXT DEFAULT 'General', so restored rows can hold
    // strings; a direct `as num?` cast threw and emptied the course catalog.
    int gradeFromRow(Map<String, dynamic> row) =>
        num.tryParse(row['grade']?.toString() ?? '')?.toInt() ?? 0;
    int publishedFromRow(Map<String, dynamic> row) =>
        num.tryParse(row['published']?.toString() ?? '')?.toInt() ?? 0;

    test('TEXT grade falls back to 0 instead of throwing', () {
      expect(gradeFromRow({'grade': 'General'}), 0);
      expect(gradeFromRow({'grade': 'Grade 9'}), 0);
      expect(gradeFromRow({}), 0);
      expect(gradeFromRow({'grade': null}), 0);
    });

    test('int and numeric-string grades parse', () {
      expect(gradeFromRow({'grade': 9}), 9);
      expect(gradeFromRow({'grade': '9'}), 9);
    });

    test('published parses int, numeric string, and bool-ish values safely', () {
      expect(publishedFromRow({'published': 1}), 1);
      expect(publishedFromRow({'published': '1'}), 1);
      expect(publishedFromRow({'published': 'true'}), 0);
      expect(publishedFromRow({}), 0);
    });

    test('Course.fromJson maps TEXT grade to 0', () {
      final c = Course.fromJson(const {
        'id': 'c1',
        'title': 'Fractions',
        'subject': 'General',
        'grade': 'General',
        'language': 'en',
        'published': 1,
      });
      expect(c.grade, 0);
      expect(c.published, 1);
    });
  });

  group('multiAnswerKey (web-builder singular-list shape)', () {
    // The web builder stores multi answers as a list under SINGULAR
    // correct_answer, and _answer_key echoes it. Reading only the plural
    // key dropped the answers and graded perfect responses wrong.
    test('reads the list from either key', () {
      expect(multiAnswerKey(const {'correct_answers': ['a', 'b']}), ['a', 'b']);
      expect(multiAnswerKey(const {'correct_answer': ['a', 'b']}), ['a', 'b']);
    });

    test('returns null when neither key holds a list', () {
      expect(multiAnswerKey(const {}), isNull);
      expect(multiAnswerKey(const {'correct_answer': 0}), isNull);
      expect(multiAnswerKey(const {'correct_answer': 'Paris'}), isNull);
    });

    test('two correct answers selected both grade correct', () {
      // Mirrors _isAnswerCorrect's multi branch with the injected key.
      final key = multiAnswerKey(const {'correct_answer': ['Paris', 'London']})!
          .map((e) => e.toString())
          .toList();
      final selected = ['Paris', 'London'];
      expect(selected.length == key.length && selected.every(key.contains), isTrue);
      expect((['Paris']).length == key.length, isFalse); // subset is not enough
    });
  });

  group('resolveAnswerOption (server index-key mapping)', () {
    const options = ['Paris', 'London', 'Berlin'];

    test('int index resolves against original option order', () {
      expect(resolveAnswerOption(options, 0), 'Paris');
      expect(resolveAnswerOption(options, 2), 'Berlin');
    });

    test('out-of-range and empty-option indexes yield null', () {
      expect(resolveAnswerOption(options, 5), isNull);
      expect(resolveAnswerOption(options, -1), isNull);
      expect(resolveAnswerOption(const [], 0), isNull);
    });

    test('text and null values pass through', () {
      expect(resolveAnswerOption(options, 'London'), 'London');
      expect(resolveAnswerOption(options, null), isNull);
    });

    test('numeric strings matching an option stay literal, else resolve by index', () {
      // Web form stringifies indexes; option text itself may be numeric.
      expect(resolveAnswerOption(['1', '2'], '1'), '1');
      expect(resolveAnswerOption(options, '0'), 'Paris');
      expect(resolveAnswerOption(options, '9'), isNull);
    });

    test('stripped server question + raw _answer_key grades correctly', () {
      // Server strips correct_answer from questions and ships the raw key
      // separately; the player injects it before shuffling.
      final q = QuizQuestion.fromJson(const {
        'id': 'q-0',
        'type': 'mcq',
        'question': 'Capital of France?',
        'options': ['Paris', 'London', 'Berlin'],
      });
      expect(q.correctAnswer, isNull); // stripped: no key in question
      final injected =
          resolveAnswerOption(q.options, 0); // raw key {correct_answer: 0}
      expect(injected, 'Paris');
    });
  });

  group('courseDownloadFileName/courseDownloadType (offline naming seam)', () {
    CourseResource res(String id, {String? filename}) => CourseResource(
          id: id,
          courseId: 'c1',
          resourceType: CourseType.textbook,
          title: id,
          filename: filename,
          fileSize: 0,
          position: 0,
        );

    test('stable <id>.<ext> name for normal server filenames', () {
      expect(courseDownloadFileName(res('r1', filename: 'a3f2e1b0.pdf')), 'r1.pdf');
      expect(courseDownloadFileName(res('r2', filename: 'lecture-01.mp4')), 'r2.mp4');
      expect(courseDownloadFileName(res('r3', filename: 'archive.tar.gz')), 'r3.gz');
    });

    test('extensionless resources queue as the bare id (no phantom ext)', () {
      // Regression: the old inline `'.${filename.split('.').last}'` turned
      // 'abc' into the file name 'r1.abc'.
      expect(courseDownloadFileName(res('r1', filename: 'abc')), 'r1');
      expect(courseDownloadFileName(res('r1')), 'r1');
      expect(courseDownloadFileName(res('r1', filename: '')), 'r1');
      expect(courseDownloadFileName(res('r1', filename: 'abc.')), 'r1');
      expect(courseDownloadFileName(res('r1', filename: '.hidden')), 'r1');
    });

    test('type strings match ResourceType names so icons parse back', () {
      expect(courseDownloadType(CourseType.textbook), 'textbook');
      expect(courseDownloadType(CourseType.videos), 'videos');
      expect(courseDownloadType(CourseType.video), 'videos'); // deprecated alias
      expect(courseDownloadType(CourseType.quiz), 'quiz');
      expect(courseDownloadType(CourseType.pyq), 'pyq');
      expect(courseDownloadType(CourseType.notes), 'notes');
      expect(courseDownloadType(CourseType.pastPaper), 'pastPaper');
      expect(courseDownloadType(CourseType.kiwix), 'kiwix');
    });
  });
}
