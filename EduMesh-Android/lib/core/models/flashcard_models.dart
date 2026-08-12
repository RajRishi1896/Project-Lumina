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

  /// Unique deck identifier.
  final String id;

  /// Display title shown in the deck list.
  final String title;

  /// Origin of the deck: `local` or `hub`.
  final String source;

  /// Cards in display order.
  final List<FlashcardCard> cards;

  /// Pending / approved / rejected -- empty for purely local decks.
  final String submissionStatus;
  final String submissionReason;

  /// Number of cards due for review right now.
  int get dueCount => cards.where((c) => c.isDue).length;

  /// Returns a copy of this deck with the given fields replaced.
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

  /// Unique card identifier.
  final String id;

  /// Identifier of the parent [FlashcardDeck].
  final String deckId;

  /// Front (question) text.
  final String front;

  /// Back (answer) text.
  final String back;

  /// SM-2 ease factor used for review scheduling.
  final double ease;

  /// Days until the next review of this card.
  final int intervalDays;

  /// Epoch milliseconds at which the card is next due.
  final int dueAt;

  /// Whether the card is due for review now.
  bool get isDue => dueAt <= DateTime.now().millisecondsSinceEpoch;

  /// A blank card used as a default value.
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
