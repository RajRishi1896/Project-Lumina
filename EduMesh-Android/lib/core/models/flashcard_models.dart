/// Local flashcard models.
library;

/// A flashcard deck stored on this device.
class FlashcardDeck {
  const FlashcardDeck({
    required this.id,
    required this.title,
    required this.source,
    required this.cards,
    this.submissionStatus = '',
    this.submissionReason = '',
  });

  final String id;
  final String title;
  final String source;

  /// Cards in display order.
  final List<FlashcardCard> cards;

  /// Pending / approved / rejected -- empty for purely local decks.
  final String submissionStatus;
  final String submissionReason;

  int get dueCount => cards.where((c) => c.isDue).length;

  FlashcardDeck copyWith({List<FlashcardCard>? cards, String? title}) {
    return FlashcardDeck(
      id: id,
      title: title ?? this.title,
      source: source,
      cards: cards ?? this.cards,
      submissionStatus: submissionStatus,
      submissionReason: submissionReason,
    );
  }
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
  final String deckId;
  final String front;
  final String back;
  final double ease;
  final int intervalDays;
  final int dueAt;

  bool get isDue => dueAt <= DateTime.now().millisecondsSinceEpoch;

  static const FlashcardCard empty = FlashcardCard(
    id: '',
    deckId: '',
    front: '',
    back: '',
    ease: 2.5,
    intervalDays: 0,
    dueAt: 0,
  );
}
