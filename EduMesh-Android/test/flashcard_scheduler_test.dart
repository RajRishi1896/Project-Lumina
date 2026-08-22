import 'package:flutter_test/flutter_test.dart';

import 'package:edumesh_android/core/services/flashcard_scheduler.dart';

void main() {
  final dayMs = Duration(days: 1).inMilliseconds;

  test('again resets interval to 1 and lowers ease', () {
    final next = scheduleNext(ReviewGrade.again, 2.5, 10, 1000);
    expect(next.intervalDays, 1);
    expect(next.ease, closeTo(2.35, 0.001));
    expect(next.dueAt, 1000 + Duration(days: 1).inMilliseconds);
  });

  test('hard grows slowly and lowers ease', () {
    final next = scheduleNext(ReviewGrade.hard, 2.5, 10, 0);
    expect(next.intervalDays, 12);
    expect(next.ease, closeTo(2.4, 0.001));
  });

  test('good grows by ease factor', () {
    final next = scheduleNext(ReviewGrade.good, 2.5, 5, 0);
    expect(next.intervalDays, 13);
    expect(next.ease, 2.5);
  });

  test('easy grows by 1.4 and raises ease', () {
    final next = scheduleNext(ReviewGrade.easy, 2.5, 5, 0);
    expect(next.intervalDays, 7);
    expect(next.ease, closeTo(2.6, 0.001));
  });

  test('ease clamps to [1.3, 3.0]', () {
    expect(scheduleNext(ReviewGrade.easy, 2.9, 1, 0).ease, 3.0);
    expect(scheduleNext(ReviewGrade.again, 1.3, 1, 0).ease, 1.3);
  });

  test('interval never below 1', () {
    expect(scheduleNext(ReviewGrade.again, 1.3, 0, 0).intervalDays, 1);
  });

  // Cases folded from test/fix_regressions_test.dart (rating-tile semantics).

  test('brand-new card (ease 2.5, interval 0): every grade yields the minimum 1-day step', () {
    for (final grade in ReviewGrade.values) {
      final next = scheduleNext(grade, 2.5, 0, 1000);
      expect(next.intervalDays, 1,
          reason: '$grade on a new card must produce the 1-day floor');
      expect(next.dueAt, 1000 + dayMs);
    }
  });

  test('Again always yields the minimum 1-day step regardless of prior interval', () {
    expect(scheduleNext(ReviewGrade.again, 2.5, 7, 0).intervalDays, 1);
    expect(scheduleNext(ReviewGrade.again, 3.0, 365, 0).intervalDays, 1);
  });

  test('mature card (ease 2.5, interval 30): documented per-grade steps', () {
    expect(scheduleNext(ReviewGrade.hard, 2.5, 30, 0).intervalDays, 36);
    expect(scheduleNext(ReviewGrade.good, 2.5, 30, 0).intervalDays, 75);
    expect(scheduleNext(ReviewGrade.easy, 2.5, 30, 0).intervalDays, 42);
  });

  test('Easy beats Again/Hard for the same input, and beats Good when ease is low', () {
    final lowEase = 10;
    expect(scheduleNext(ReviewGrade.good, 1.3, lowEase, 0).intervalDays, 13);
    expect(scheduleNext(ReviewGrade.easy, 1.3, lowEase, 0).intervalDays, 14);

    // Good multiplies by the full ease factor, so once ease > 1.4 Good
    // outgrows Easy; assert the real behaviour so a future change is a
    // conscious decision.
    expect(
      scheduleNext(ReviewGrade.good, 2.5, 30, 0).intervalDays,
      greaterThan(scheduleNext(ReviewGrade.easy, 2.5, 30, 0).intervalDays),
    );
    for (final ease in [1.3, 2.5, 3.0]) {
      final easyStep = scheduleNext(ReviewGrade.easy, ease, 20, 0).intervalDays;
      expect(easyStep, greaterThan(scheduleNext(ReviewGrade.again, ease, 20, 0).intervalDays));
      expect(easyStep, greaterThan(scheduleNext(ReviewGrade.hard, ease, 20, 0).intervalDays));
    }
  });

  test('ease clamps at [1.3, 3.0] with in-range values moving freely', () {
    expect(scheduleNext(ReviewGrade.easy, 2.95, 10, 0).ease, 3.0);
    expect(scheduleNext(ReviewGrade.easy, 2.5, 10, 0).ease, closeTo(2.6, 1e-9));
    expect(scheduleNext(ReviewGrade.hard, 2.5, 10, 0).ease, closeTo(2.4, 1e-9));
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
}
