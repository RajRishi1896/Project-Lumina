/// SM-2 spaced-repetition scheduling for flashcards.
///
/// Pure functions -- no I/O, so the algorithm is unit-testable and the UI
/// stays fast on low-end devices.
library;

/// One review outcome, mirroring the four self-grading buttons in the UI.
enum ReviewGrade { again, hard, good, easy }

/// Scheduling state for a single card.
class CardSchedule {
  const CardSchedule({required this.ease, required this.intervalDays, required this.dueAt});

  /// Ease factor (1.3 - 3.0, default 2.5).
  final double ease;

  /// Days until the next review (0 = due now).
  final int intervalDays;

  /// Unix timestamp (milliseconds) when the card is next due.
  final int dueAt;
}

/// Computes the next schedule for a card reviewed at [reviewedAt] (ms).
CardSchedule scheduleNext(
  ReviewGrade grade,
  double ease,
  int intervalDays,
  int reviewedAt,
) {
  var nextEase = ease;
  var nextInterval = intervalDays;

  switch (grade) {
    case ReviewGrade.again:
      nextInterval = 1;
      nextEase -= 0.15;
    case ReviewGrade.hard:
      nextInterval = (intervalDays * 1.2).round();
      nextEase -= 0.10;
    case ReviewGrade.good:
      nextInterval = (intervalDays * nextEase).round();
    case ReviewGrade.easy:
      nextInterval = (intervalDays * 1.4).round();
      nextEase += 0.10;
  }

  if (nextInterval < 1) nextInterval = 1;
  if (nextEase < 1.3) nextEase = 1.3;
  if (nextEase > 3.0) nextEase = 3.0;

  final dayMs = const Duration(days: 1).inMilliseconds;
  return CardSchedule(
    ease: nextEase,
    intervalDays: nextInterval,
    dueAt: reviewedAt + nextInterval * dayMs,
  );
}
