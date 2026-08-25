/// Local flashcard models.
library;

/// A flashcard deck stored on this device.
class FlashcardDeck {
  const FlashcardDeck({
    required this.id,
    required this.title,
    required this.source,
    required this.cards,
    this.subject = '',
    this.submissionStatus = '',
    this.submissionReason = '',
    this.lastStudiedAt = 0,
  });

  final String id;

  final String title;

  /// Optional free-text subject label shown alongside the deck title.
  final String subject;

  /// Origin of the deck: `local` or `hub`.
  final String source;

  final List<FlashcardCard> cards;

  /// Pending / approved / rejected: empty for purely local decks.
  final String submissionStatus;
  final String submissionReason;

  /// Epoch ms of the deck's most recent card review; 0 = never studied.
  final int lastStudiedAt;

  int get dueCount => cards.where((c) => c.isDue).length;

  /// Cards whose SM-2 interval has reached graduation (>= 21 days).
  int get masteredCount => cards.where((c) => c.intervalDays >= 21).length;

  /// 0-100 share of cards already cleared for today (not due) — the deck
  /// progress bar fills as the student works through today's reviews.
  int get progressPercent => cards.isEmpty
      ? 0
      : ((cards.where((c) => !c.isDue).length * 100) / cards.length).round();
}

/// A single front/back card with its review schedule state.
class FlashcardCard {
  const FlashcardCard({
    required this.id,
    required this.deckId,
    required this.front,
    required this.back,
    required this.ease,
    required this.intervalDays,
    required this.dueAt,
  });

  final String id;

  /// Identifier of the parent [FlashcardDeck].
  final String deckId;

  final String front;

  final String back;

  /// SM-2 ease factor used for review scheduling.
  final double ease;

  /// Days until the next review of this card.
  final int intervalDays;

  /// Epoch milliseconds at which the card is next due.
  final int dueAt;

  bool get isDue => dueAt <= DateTime.now().millisecondsSinceEpoch;
}
