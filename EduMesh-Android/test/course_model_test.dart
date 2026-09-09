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
      expect(r.resourceType, CourseType.video);
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

    test('resource_type parsing: case-insensitive, past_paper alias, unknown falls back to textbook', () {
      int typeOf(String raw) => CourseResource.fromJson({'resource_type': raw}).resourceType.index;
      expect(typeOf('TEXTBOOK'), CourseType.textbook.index);
      expect(typeOf('Video'), CourseType.video.index);
      expect(typeOf('quiz'), CourseType.quiz.index);
      expect(typeOf('past_paper'), CourseType.pastPaper.index);
      expect(typeOf('pastpaper'), CourseType.pastPaper.index);
      expect(typeOf('mystery'), CourseType.textbook.index);
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
}
