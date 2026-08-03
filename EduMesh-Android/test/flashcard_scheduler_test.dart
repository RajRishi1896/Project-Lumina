import 'package:flutter_test/flutter_test.dart';

import 'package:edumesh_android/core/services/flashcard_scheduler.dart';

void main() {
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
}
