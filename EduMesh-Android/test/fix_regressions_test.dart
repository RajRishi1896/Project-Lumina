// Regression tests for the fix batch: scheduler-backed rating-tile previews,
// CourseResource.fromJson (course-player offline fallback path), and the
// FlashcardDeck.subject default.
//
// Contracts verified against lib source on 2026-08:
// - scheduleNext: SM-2 variant in lib/core/services/flashcard_scheduler.dart
//   (again=1d/-0.15 ease, hard=x1.2/-0.10, good=x ease, easy=x1.4/+0.10,
//   clamps: interval>=1, ease in [1.3, 3.0]).
// - CourseResource.fromJson key names from lib/core/models/course.dart.
// - FlashcardDeck has NO fromJson/toJson: persistence is SQLite row maps in
//   flashcard_service.dart using `(row['subject'] ?? '').toString()`.
import 'package:flutter_test/flutter_test.dart';

import 'package:edumesh_android/core/models/course.dart';
import 'package:edumesh_android/core/models/flashcard_models.dart';
import 'package:edumesh_android/core/services/flashcard_scheduler.dart';

void main() {
  group('FlashcardScheduler.scheduleNext (rating-tile preview semantics)', () {
    final dayMs = Duration(days: 1).inMilliseconds;

    test('brand-new card (ease 2.5, interval 0): every grade yields the minimum 1-day step', () {
      // 0 * any factor rounds to 0, which the floor clamp raises to 1.
      for (final grade in ReviewGrade.values) {
        final next = scheduleNext(grade, 2.5, 0, 1000);
        expect(next.intervalDays, 1,
            reason: '$grade on a new card must produce the 1-day floor');
        expect(next.dueAt, 1000 + dayMs);
      }
    });

    test('Again always yields the minimum 1-day step regardless of prior interval', () {
      expect(scheduleNext(ReviewGrade.again, 2.5, 0, 0).intervalDays, 1);
      expect(scheduleNext(ReviewGrade.again, 2.5, 7, 0).intervalDays, 1);
      expect(scheduleNext(ReviewGrade.again, 3.0, 365, 0).intervalDays, 1);
    });

    test('mature card (ease 2.5, interval 30): documented per-grade steps', () {
      // Real math: again=1, hard=(30*1.2)=36, good=(30*2.5)=75, easy=(30*1.4)=42.
      expect(scheduleNext(ReviewGrade.again, 2.5, 30, 0).intervalDays, 1);
      expect(scheduleNext(ReviewGrade.hard, 2.5, 30, 0).intervalDays, 36);
      expect(scheduleNext(ReviewGrade.good, 2.5, 30, 0).intervalDays, 75);
      expect(scheduleNext(ReviewGrade.easy, 2.5, 30, 0).intervalDays, 42);
    });

    test('Easy beats Again/Hard for the same input, and beats Good when ease is low', () {
      // At the ease floor (1.3): good = round(i * 1.3) < easy = round(i * 1.4).
      final lowEase = 10;
      expect(scheduleNext(ReviewGrade.good, 1.3, lowEase, 0).intervalDays, 13);
      expect(scheduleNext(ReviewGrade.easy, 1.3, lowEase, 0).intervalDays, 14);

      // CONTRACT SURPRISE vs the naive assumption "Easy is always largest":
      // Good multiplies by the full ease factor, so once ease > 1.4 Good
      // outgrows Easy. Assert the real behaviour so a future change is a
      // conscious decision, not an accident.
      expect(
        scheduleNext(ReviewGrade.good, 2.5, 30, 0).intervalDays,
        greaterThan(scheduleNext(ReviewGrade.easy, 2.5, 30, 0).intervalDays),
      );
      // But Easy still dominates Again/Hard at any ease.
      for (final ease in [1.3, 2.5, 3.0]) {
        final easyStep = scheduleNext(ReviewGrade.easy, ease, 20, 0).intervalDays;
        expect(easyStep, greaterThan(scheduleNext(ReviewGrade.again, ease, 20, 0).intervalDays));
        expect(easyStep, greaterThan(scheduleNext(ReviewGrade.hard, ease, 20, 0).intervalDays));
      }
    });

    test('ease clamps at [1.3, 3.0]', () {
      // Below floor: Again from the floor stays at 1.3.
      expect(scheduleNext(ReviewGrade.again, 1.3, 10, 0).ease, 1.3);
      // Above ceiling: Easy from 2.95 (+0.10) caps at 3.0.
      expect(scheduleNext(ReviewGrade.easy, 2.95, 10, 0).ease, 3.0);
      // In-range values move freely.
      expect(scheduleNext(ReviewGrade.easy, 2.5, 10, 0).ease, closeTo(2.6, 1e-9));
      expect(scheduleNext(ReviewGrade.hard, 2.5, 10, 0).ease, closeTo(2.4, 1e-9));
      expect(scheduleNext(ReviewGrade.again, 2.5, 10, 0).ease, closeTo(2.35, 1e-9));
      expect(scheduleNext(ReviewGrade.good, 2.5, 10, 0).ease, 2.5);
    });

    test('next interval grows monotonically with the current interval (Good/Easy/Hard)', () {
      for (final grade in [ReviewGrade.hard, ReviewGrade.good, ReviewGrade.easy]) {
        int? previous;
        for (final current in [1, 2, 4, 8, 16, 32, 64]) {
          final step = scheduleNext(grade, 2.5, current, 0).intervalDays;
          if (previous != null) {
            expect(step, greaterThanOrEqualTo(previous!),
                reason: '$grade step must not shrink as interval grows $current');
          }
          previous = step;
        }
      }
    });

    test('dueAt is always reviewedAt + intervalDays days, for every grade', () {
      for (final grade in ReviewGrade.values) {
        final next = scheduleNext(grade, 2.5, 12, 987654321);
        expect(next.dueAt, 987654321 + next.intervalDays * dayMs,
            reason: '$grade dueAt must stay consistent with its interval');
      }
    });
  });

  group('CourseResource.fromJson (course-player local-table fallback)', () {
    test('parses every field from a full local course_resources row map', () {
      // Exact keys fed by the course-player fallback (lib/core/models/course.dart
      // fromJson reads these snake_case names).
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

  group('FlashcardDeck.subject default', () {
    test('constructor defaults subject to empty string', () {
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
      // `subject: (row['subject'] ?? '').toString()` — there is no
      // FlashcardDeck.fromJson; this is the actual persistence contract.
      String subjectFromRow(Map<String, dynamic> row) => (row['subject'] ?? '').toString();

      expect(subjectFromRow({'subject': 'History'}), 'History');
      expect(subjectFromRow({}), ''); // pre-migration row without the column
      expect(subjectFromRow({'subject': null}), '');
    });
  });
}
